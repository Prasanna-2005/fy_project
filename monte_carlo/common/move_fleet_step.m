function [uavs, tasks] = move_fleet_step(uavs, tasks, t, dt, cfg)
% MOVE_FLEET_STEP  One motion step for every allocator.
% Overload stretch matches Zeng et al.: if the queue still holding the
% active task is longer than nominal capacity, that task takes exec/delta.
[delta, nomCap] = overload_params(cfg);

for i = 1:numel(uavs)
    j = uavs(i).assignedTask;
    if j == 0
        if ~isempty(uavs(i).queue)
            uavs(i).assignedTask = uavs(i).queue(1);
            j = uavs(i).assignedTask;
        else
            continue
        end
    end
    target = tasks(j).location;
    p = uavs(i).position;
    d = norm(target - p);
    if d > 1e-6
        step = uavs(i).speed * dt;
        if step >= d
            uavs(i).position = target;
        else
            uavs(i).position = p + (target - p) / d * step;
        end
    end
    if norm(uavs(i).position - target) < 1e-6
        if ~isFeasible(tasks(j).requiredCap, uavs(i).capabilities)
            continue
        end
        % The clock belongs to this visit only. A start time inherited
        % from another aircraft must not count as work done here.
        if ~isfield(tasks, 'onStationUAV')
            for k = 1:numel(tasks)
                tasks(k).onStationUAV = 0;
            end
        end
        if isempty(tasks(j).onStationUAV) || tasks(j).onStationUAV ~= i || isnan(tasks(j).arrivalTime)
            tasks(j).onStationUAV = i;
            tasks(j).arrivalTime = t;
        end
        effectiveExecTime = stretched_exec(tasks(j).execTime, numel(uavs(i).queue), delta, nomCap);
        if (t - tasks(j).arrivalTime) >= effectiveExecTime
            tasks(j).status = 'complete';
            tasks(j).completeTime = t;
            tasks(j).onStationUAV = 0;
            uavs(i).queue = uavs(i).queue(uavs(i).queue ~= j);
            if ~isempty(uavs(i).queue)
                uavs(i).assignedTask = uavs(i).queue(1);
            else
                uavs(i).assignedTask = 0;
            end
        end
    end
end
end

function ok = isFeasible(requiredCap, uavCapabilities)
ok = all(ismember(requiredCap, uavCapabilities));
end
