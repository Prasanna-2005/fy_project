function capChanges = generate_attack_events_count(cfg, nAttacks, rngSeed)
% GENERATE_ATTACK_EVENTS_COUNT  Exact-count version of the local random
% attack generator. The BDTR paper does not disclose its event schedule;
% this supports a transparent sensitivity analysis rather than claiming one.

if nargin < 3, rngSeed = 42; end
rng(rngSeed, 'twister');

slots = struct('uavIndex', {}, 'capability', {});
for i = 1:numel(cfg.uav)
    for c = 1:numel(cfg.uav(i).capabilities)
        slots(end+1) = struct('uavIndex', i, ...
            'capability', cfg.uav(i).capabilities{c}); %#ok<AGROW>
    end
end

nAttacks = max(0, min(round(nAttacks), numel(slots)));
if nAttacks == 0
    capChanges = struct('uavIndex', {}, 'capability', {}, 'changeTime', {});
    return;
end

pick = randperm(numel(slots), nAttacks);
tMin = 0.15 * cfg.sim.tEnd;
tMax = 0.60 * cfg.sim.tEnd;
times = sort(tMin + (tMax - tMin) * rand(1, nAttacks));
times = round(times / cfg.sim.dt) * cfg.sim.dt;

capChanges = struct('uavIndex', {}, 'capability', {}, 'changeTime', {});
for k = 1:nAttacks
    capChanges(k) = struct('uavIndex', slots(pick(k)).uavIndex, ...
        'capability', slots(pick(k)).capability, 'changeTime', times(k));
end
end
