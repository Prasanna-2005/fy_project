function result = sim(cfg, strategy)
% SIM  Run one full mission timeline under the RRAM policy (Headless Batch).
% strategy: 'rram' (Section 1 of BDTR_Baseline_Methods.md)

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'common'));

if nargin < 1 || isempty(cfg)
    cfg = common_config('rram');
end
if nargin < 2 || isempty(strategy)
    strategy = 'rram';
end
if ~strcmp(strategy, 'rram')
    error('sim:unknownStrategy', 'Expected strategy "rram", got "%s".', strategy);
end

uavs  = makeFleet(cfg);
tasks = makeTaskSet(cfg);

events = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});

% ---- Initial allocation at t=0: RRAM random draw for tasks released at t=0 ----
initTasks = find([tasks.releaseTime] <= 0);
pendingTasks = find([tasks.releaseTime] > 0);
for pIdx = pendingTasks
    tasks(pIdx).status = 'pending';
end

if ~isempty(initTasks)
    [uavs, tasks, ev0] = rramInitialAllocation(uavs, tasks, initTasks);
    events = [events, ev0];
end

for t = 0:cfg.sim.dt:cfg.sim.tEnd

    % ---- Dynamic Midway Task Release ----
    for j = 1:numel(tasks)
        if strcmp(tasks(j).status, 'pending') && t >= tasks(j).releaseTime
            [uavs, tasks, evRel] = rramAssignSingleTask(uavs, tasks, j, t);
            events = [events, evRel]; %#ok<AGROW>
        end
    end

    [uavs, justChanged, degradedUAVs, degradedCaps] = fireCapabilityChanges(uavs, cfg, t);

    % ---- Reactive trigger: fires when capability loss lands
    if justChanged
        for dIdx = 1:numel(degradedUAVs)
            u_fail = degradedUAVs(dIdx);
            events(end+1) = struct('time', t, 'taskIdx', 0, 'oldUAV', 0, 'newUAV', u_fail, ...
                'trigger', 'degradation', 'reason', degradedCaps{dIdx}); %#ok<AGROW>
            [uavs, tasks, evChange] = rramReactiveReallocation(uavs, tasks, u_fail, t);
            events = [events, evChange]; %#ok<AGROW>
        end
    end

    % ---- Deadline expiry sweep: fail any unfinished task whose deadline has passed
    for j = 1:numel(tasks)
        if ~strcmp(tasks(j).status, 'complete') && ~strcmp(tasks(j).status, 'failed') && ~strcmp(tasks(j).status, 'pending')
            if t >= tasks(j).deadline
                tasks(j).status = 'failed';
                i = tasks(j).assignedUAV;
                if i > 0 && i <= numel(uavs)
                    uavs(i).queue = uavs(i).queue(uavs(i).queue ~= j);
                    if uavs(i).assignedTask == j
                        if ~isempty(uavs(i).queue)
                            uavs(i).assignedTask = uavs(i).queue(1);
                        else
                            uavs(i).assignedTask = 0;
                        end
                    end
                end
            end
        end
    end

    [uavs, tasks] = moveFleet(uavs, tasks, t, cfg.sim.dt);
end

result.uavs     = uavs;
result.tasks    = tasks;
result.events   = events;
result.metrics  = computeMissionMetrics(uavs, tasks, events, cfg);
result.strategy = strategy;

end

%% ======================= RRAM ALLOCATION LOGIC =======================

function [uavs, tasks, ev0] = rramInitialAllocation(uavs, tasks, taskIndices)
if nargin < 3 || isempty(taskIndices)
    taskIndices = 1:numel(tasks);
end
ev0 = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});
LARGE_PRIME = 2654435761;

for idx = 1:numel(taskIndices)
    k = taskIndices(idx);
    req = tasks(k).requiredCap;
    cand = [];
    for u = 1:numel(uavs)
        if isFeasible(req, uavs(u).capabilities)
            cand(end+1) = u; %#ok<AGROW>
        end
    end
    if isempty(cand)
        tasks(k).status = 'atrisk';
        tasks(k).atriskReason = 'Capability';
    else
        drawIdx = mod(k * LARGE_PRIME, numel(cand)) + 1;
        u_target = cand(drawIdx);
        uavs(u_target).queue(end+1) = k;
        tasks(k).assignedUAV = u_target;
        tasks(k).status = 'assigned';
        ev0(end+1) = struct('time', 0, 'taskIdx', k, 'oldUAV', 0, 'newUAV', u_target, ...
            'trigger', 'initial', 'reason', 'RRAM-Initial'); %#ok<AGROW>
    end
end

for i = 1:numel(uavs)
    if ~isempty(uavs(i).queue)
        uavs(i).assignedTask = uavs(i).queue(1);
    end
end
end

function [uavs, tasks, evRel] = rramAssignSingleTask(uavs, tasks, k, t)
evRel = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});
LARGE_PRIME = 2654435761;
req = tasks(k).requiredCap;
cand = [];
for u = 1:numel(uavs)
    if isFeasible(req, uavs(u).capabilities)
        cand(end+1) = u; %#ok<AGROW>
    end
end
if isempty(cand)
    tasks(k).status = 'atrisk';
    tasks(k).atriskReason = 'Capability';
else
    drawIdx = mod(k * LARGE_PRIME, numel(cand)) + 1;
    u_target = cand(drawIdx);
    uavs(u_target).queue(end+1) = k;
    tasks(k).assignedUAV = u_target;
    tasks(k).status = 'assigned';
    if uavs(u_target).assignedTask == 0
        uavs(u_target).assignedTask = k;
    end
    evRel(end+1) = struct('time', t, 'taskIdx', k, 'oldUAV', 0, 'newUAV', u_target, ...
        'trigger', 'reactive', 'reason', 'RRAM-MidwayRelease'); %#ok<AGROW>
end
end

function [uavs, tasks, evChange] = rramReactiveReallocation(uavs, tasks, u_fail, t)
evChange = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});
LARGE_PRIME = 2654435761;

q_fail = uavs(u_fail).queue;
k_invalid = [];
for idx = 1:numel(q_fail)
    k = q_fail(idx);
    if ~isFeasible(tasks(k).requiredCap, uavs(u_fail).capabilities)
        k_invalid(end+1) = k; %#ok<AGROW>
    end
end

if isempty(k_invalid)
    return;
end

% Remove invalid tasks from u_fail''s queue
uavs(u_fail).queue = setdiff(uavs(u_fail).queue, k_invalid, 'stable');
if ismember(uavs(u_fail).assignedTask, k_invalid)
    if ~isempty(uavs(u_fail).queue)
        uavs(u_fail).assignedTask = uavs(u_fail).queue(1);
    else
        uavs(u_fail).assignedTask = 0;
    end
end

% Reallocate each invalid task to a capable UAV via RRAM draw
for idx = 1:numel(k_invalid)
    k = k_invalid(idx);
    tasks(k).arrivalTime = NaN;
    req = tasks(k).requiredCap;
    cand = [];
    for u = 1:numel(uavs)
        if isFeasible(req, uavs(u).capabilities)
            cand(end+1) = u; %#ok<AGROW>
        end
    end
    if isempty(cand)
        tasks(k).assignedUAV = 0;
        tasks(k).status = 'atrisk';
        tasks(k).atriskReason = 'Capability';
    else
        drawIdx = mod(k * LARGE_PRIME, numel(cand)) + 1;
        u_target = cand(drawIdx);
        uavs(u_target).queue(end+1) = k;
        tasks(k).assignedUAV = u_target;
        tasks(k).status = 'assigned';
        tasks(k).atriskReason = '';
        if uavs(u_target).assignedTask == 0
            uavs(u_target).assignedTask = k;
        end
        evChange(end+1) = struct('time', t, 'taskIdx', k, 'oldUAV', u_fail, 'newUAV', u_target, ...
            'trigger', 'reactive', 'reason', 'RRAM-Reassign'); %#ok<AGROW>
    end
end
end

%% ======================= STATE CONSTRUCTION =======================

function uavs = makeFleet(cfg)
n = numel(cfg.uav);
uavs = repmat(struct('name','', 'position',[0 0 0], 'capabilities',{{}}, ...
    'speed',0, 'assignedTask',0, 'queue',[]), 1, n);
for i = 1:n
    uavs(i).name         = cfg.uav(i).name;
    uavs(i).position     = cfg.uav(i).position;
    uavs(i).capabilities = cfg.uav(i).capabilities;
    uavs(i).speed        = cfg.uav(i).speed;
    uavs(i).assignedTask = 0;
    uavs(i).queue        = [];
end
end

function tasks = makeTaskSet(cfg)
n = numel(cfg.task);
tasks = repmat(struct('name','', 'location',[0 0 0], 'requiredCap',{{}}, ...
    'execTime',0, 'priority',1, 'deadline',Inf, 'assignedUAV',0, ...
    'status','unassigned', 'atriskReason','', ...
    'completeTime',NaN, 'arrivalTime',NaN, 'releaseTime',0), 1, n);
for j = 1:n
    tasks(j).name        = cfg.task(j).name;
    tasks(j).location    = cfg.task(j).location;
    tasks(j).requiredCap = cfg.task(j).requiredCap;
    tasks(j).execTime    = cfg.task(j).execTime;
    tasks(j).priority    = cfg.task(j).priority;
    tasks(j).deadline    = cfg.task(j).deadline;
    if isfield(cfg.task(j), 'releaseTime') && ~isempty(cfg.task(j).releaseTime)
        tasks(j).releaseTime = cfg.task(j).releaseTime;
    else
        tasks(j).releaseTime = 0;
    end
end
end

%% ======================= FEASIBILITY =======================

function ok = isFeasible(requiredCap, uavCapabilities)
ok = all(ismember(requiredCap, uavCapabilities));
end

%% ======================= CAPABILITY CHANGES =======================

function [uavs, changed, degradedUAVs, degradedCaps] = fireCapabilityChanges(uavs, cfg, t)
changed = false;
degradedUAVs = [];
degradedCaps = {};

if isfield(cfg, 'capabilityChanges')
    cList = cfg.capabilityChanges;
elseif isfield(cfg, 'capabilityChange')
    cList = cfg.capabilityChange;
else
    return;
end

for k = 1:numel(cList)
    cc = cList(k);
    if t >= cc.changeTime
        i = cc.uavIndex;
        if ismember(cc.capability, uavs(i).capabilities)
            uavs(i).capabilities = uavs(i).capabilities(~strcmp(uavs(i).capabilities, cc.capability));
            changed = true;
            degradedUAVs(end+1) = i; %#ok<AGROW>
            degradedCaps{end+1} = cc.capability; %#ok<AGROW>
        end
    end
end
end

%% ======================= MOVEMENT =======================

function [uavs, tasks] = moveFleet(uavs, tasks, t, dt)
for i = 1:numel(uavs)
    j = uavs(i).assignedTask;
    if j == 0
        if ~isempty(uavs(i).queue)
            uavs(i).assignedTask = uavs(i).queue(1);
            j = uavs(i).assignedTask;
        else
            continue;
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
            continue;
        end
        if isnan(tasks(j).arrivalTime)
            tasks(j).arrivalTime = t;
        end
        if (t - tasks(j).arrivalTime) >= tasks(j).execTime
            tasks(j).status = 'complete';
            tasks(j).completeTime = t;
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

%% ======================= METRICS =======================

function metrics = computeMissionMetrics(uavs, tasks, events, cfg)
nT = numel(tasks);

feasibleCount = 0;
for j = 1:nT
    if strcmp(tasks(j).status, 'complete')
        feasibleCount = feasibleCount + 1;
    elseif strcmp(tasks(j).status, 'assigned')
        i = tasks(j).assignedUAV;
        if i > 0 && i <= numel(uavs) && isFeasible(tasks(j).requiredCap, uavs(i).capabilities)
            feasibleCount = feasibleCount + 1;
        end
    end
end
metrics.feasibilityRate = feasibleCount / nT;
metrics.completionRate  = sum(strcmp({tasks.status}, 'complete')) / nT;
metrics.failedRate      = sum(strcmp({tasks.status}, 'failed')) / nT;
metrics.reallocationCount = sum(strcmp({events.trigger}, 'reactive') | strcmp({events.trigger}, 'reactive-preempt'));
metrics.preemptionCount   = sum(strcmp({events.trigger}, 'reactive-preempt'));

completeTimes = [tasks(strcmp({tasks.status}, 'complete')).completeTime];
if isempty(completeTimes)
    metrics.meanCompletionTime = NaN;
else
    metrics.meanCompletionTime = mean(completeTimes);
end

% Paper metrics (CRI, R_task, R_time, ThroughputRecovery)
pm = compute_paper_metrics(tasks, events, cfg, cfg.sim.tEnd);
metrics.R_task = pm.R_task;
metrics.R_time = pm.R_time;
metrics.CRI    = pm.CRI;
metrics.throughputRecovery = pm.throughputRecovery;
end
