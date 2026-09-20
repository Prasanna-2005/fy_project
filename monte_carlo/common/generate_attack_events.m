function capChanges = generate_attack_events(cfg, strength, pattern, rngSeed)
% GENERATE_ATTACK_EVENTS  Parameterized failure-rate generator.
%   Replaces the hardcoded 2-event capabilityChanges with a stochastic
%   attack schedule matching the BDTR paper''s experimental design:
%     - strength: fraction of total capability-slots to degrade (0.2/0.3/0.4)
%     - pattern:  'random', 'balanced', or 'directed'
%     - rngSeed:  integer seed for reproducibility across Monte Carlo runs
%
%   Returns: struct array with fields {uavIndex, capability, changeTime}

    if nargin < 4, rngSeed = 42; end
    if nargin < 3 || isempty(pattern), pattern = 'random'; end
    if nargin < 2 || isempty(strength), strength = 0.3; end

    rng(rngSeed, 'twister');

    nUAV = numel(cfg.uav);
    tEnd = cfg.sim.tEnd;

    % ---- Enumerate all (UAV, capability) slots in the fleet ----
    slots = struct('uavIndex', {}, 'capability', {});
    for i = 1:nUAV
        for c = 1:numel(cfg.uav(i).capabilities)
            slots(end+1) = struct('uavIndex', i, ...
                'capability', cfg.uav(i).capabilities{c}); %#ok<AGROW>
        end
    end
    totalSlots = numel(slots);

    % Number of attacks = round(strength * totalSlots), at least 1
    nAttacks = max(1, round(strength * totalSlots));
    nAttacks = min(nAttacks, totalSlots); % can''t degrade more than exist

    % ---- Select which slots get attacked, based on pattern ----
    switch lower(pattern)
        case 'random'
            % Uniform random draw of nAttacks slots
            perm = randperm(totalSlots);
            attackIdx = perm(1:nAttacks);

        case 'balanced'
            % Spread attacks evenly across UAVs (round-robin)
            attackIdx = [];
            uavSlotMap = cell(1, nUAV);
            for s = 1:totalSlots
                u = slots(s).uavIndex;
                uavSlotMap{u}(end+1) = s;
            end
            % Shuffle each UAV''s slots
            for u = 1:nUAV
                uavSlotMap{u} = uavSlotMap{u}(randperm(numel(uavSlotMap{u})));
            end
            uavPtr = ones(1, nUAV);
            uavOrder = randperm(nUAV);
            uidx = 1;
            while numel(attackIdx) < nAttacks
                u = uavOrder(uidx);
                if uavPtr(u) <= numel(uavSlotMap{u})
                    attackIdx(end+1) = uavSlotMap{u}(uavPtr(u)); %#ok<AGROW>
                    uavPtr(u) = uavPtr(u) + 1;
                end
                uidx = mod(uidx, nUAV) + 1;
                % Safety: break if we've exhausted all slots
                if all(uavPtr > cellfun(@numel, uavSlotMap))
                    break;
                end
            end

        case 'directed'
            % Directed Attack: concentrates failures on one payload type across the fleet
            % (eliminates a whole capability class, causing the fastest collapse).
            allPayloadTypes = unique({slots.capability});

            % Determine target priority by fleet task demand
            taskCaps = {};
            for j = 1:numel(cfg.task)
                taskCaps = [taskCaps, cfg.task(j).requiredCap]; %#ok<AGROW>
            end
            typeDemand = zeros(1, numel(allPayloadTypes));
            for pt = 1:numel(allPayloadTypes)
                typeDemand(pt) = sum(strcmp(taskCaps, allPayloadTypes{pt}));
            end
            [~, targetOrder] = sort(typeDemand, 'descend');

            attackIdx = [];
            for ptIdx = targetOrder
                targetType = allPayloadTypes{ptIdx};
                matchingSlots = find(strcmp({slots.capability}, targetType));
                % Randomize which UAVs lose it first if nAttacks < count
                matchingSlots = matchingSlots(randperm(numel(matchingSlots)));
                for s = matchingSlots
                    attackIdx(end+1) = s; %#ok<AGROW>
                    if numel(attackIdx) >= nAttacks
                        break;
                    end
                end
                if numel(attackIdx) >= nAttacks
                    break;
                end
            end

        otherwise
            error('generate_attack_events:badPattern', ...
                'Unknown pattern "%s". Use random/balanced/directed.', pattern);
    end

    % ---- Generate attack times: spread across [15%..60%] of tEnd ----
    tMin = 0.15 * tEnd;
    tMax = 0.60 * tEnd;
    attackTimes = sort(tMin + (tMax - tMin) * rand(1, numel(attackIdx)));
    % Round to nearest dt for clean event alignment
    attackTimes = round(attackTimes / cfg.sim.dt) * cfg.sim.dt;

    % ---- Build output struct array ----
    capChanges = struct('uavIndex', {}, 'capability', {}, 'changeTime', {});
    for k = 1:numel(attackIdx)
        s = slots(attackIdx(k));
        capChanges(end+1) = struct( ...
            'uavIndex',  s.uavIndex, ...
            'capability', s.capability, ...
            'changeTime', attackTimes(k)); %#ok<AGROW>
    end

    rng('shuffle'); % Restore non-deterministic RNG state
end
