function result = sim(cfg, strategy, visualize)
% SIM  Run one full mission timeline under the BDTR policy.
% strategy: 'bdtr' (Section 2 of BDTR_Baseline_Methods.md)
%
% Implements Algorithm 1: Bidirectional Task Reallocation (BDTR)
%   - Phase 1: Feasibility Restoration (reactive offloading of K_invalid
%     from u_fail to argmin-load capable UAVs, priority descending).
%   - Phase 2: Residual Capacity Exploitation (pulls tasks back from
%     argmax-load donors to u_fail while |Q_d| - |Q_fail| >= 2).
%   - Deterministic tie-breaking per Section 5.2.
%   - Time-stepped flight and execution matching canonical scenario.

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'common'));

if nargin < 1 || isempty(cfg)
    cfg = common_config('bdtr');
end
if nargin < 2 || isempty(strategy)
    strategy = 'bdtr';
end
if nargin < 3
    visualize = cfg.sim.visualize;
end
if ~strcmp(strategy, 'bdtr')
    error('sim:unknownStrategy', 'Expected strategy "bdtr", got "%s".', strategy);
end

uavs  = makeFleet(cfg);
tasks = makeTaskSet(cfg);

events = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});

% ---- Initial allocation at t=0: BDTR Phase 1 min-load assignment for tasks released at t=0 ----
initTasks = find([tasks.releaseTime] <= 0);
pendingTasks = find([tasks.releaseTime] > 0);
for pIdx = pendingTasks
    tasks(pIdx).status = 'pending';
end

if ~isempty(initTasks)
    [uavs, tasks, ev0] = bdtrInitialAllocation(uavs, tasks, initTasks);
    events = [events, ev0];
end

if visualize
    rs = initRender(cfg, strategy);
end

for t = 0:cfg.sim.dt:cfg.sim.tEnd

    % ---- Dynamic Midway Task Release ----
    for j = 1:numel(tasks)
        if strcmp(tasks(j).status, 'pending') && t >= tasks(j).releaseTime
            [uavs, tasks, evRel] = bdtrAssignSingleTask(uavs, tasks, j, t);
            events = [events, evRel]; %#ok<AGROW>
        end
    end

    [uavs, justChanged, degradedUAVs, degradedCaps] = fireCapabilityChanges(uavs, cfg, t);

    % ---- Reactive trigger: on the tick capability loss lands, run BDTR Algorithm 1
    if justChanged
        for dIdx = 1:numel(degradedUAVs)
            u_fail = degradedUAVs(dIdx);
            events(end+1) = struct('time', t, 'taskIdx', 0, 'oldUAV', 0, 'newUAV', u_fail, ...
                'trigger', 'degradation', 'reason', degradedCaps{dIdx}); %#ok<AGROW>
            [uavs, tasks, evBDTR] = bdtrReallocation(uavs, tasks, u_fail, t);
            events = [events, evBDTR]; %#ok<AGROW>
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

    if visualize
        renderFrame(rs, uavs, tasks, t, events);
        pause(cfg.sim.playback * cfg.sim.dt);
    end
end

result.uavs     = uavs;
result.tasks    = tasks;
result.events   = events;
result.metrics  = computeMissionMetrics(uavs, tasks, events, cfg);
result.strategy = strategy;

end

%% ======================= BDTR ALGORITHM LOGIC =======================

function [uavs, tasks, ev0] = bdtrInitialAllocation(uavs, tasks, taskIndices)
if nargin < 3 || isempty(taskIndices)
    taskIndices = 1:numel(tasks);
end
ev0 = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});

subPriorities = [tasks(taskIndices).priority];
[~, ord] = sortrows([-subPriorities(:), taskIndices(:)]);
orderedTasks = taskIndices(ord);

for idx = 1:numel(orderedTasks)
    k = orderedTasks(idx);
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
        loads = arrayfun(@(u) numel(u.queue), uavs(cand));
        minLoad = min(loads);
        candMin = cand(loads == minLoad);
        u_target = min(candMin); % tie-break lowest UAV index
        uavs(u_target).queue(end+1) = k;
        tasks(k).assignedUAV = u_target;
        tasks(k).status = 'assigned';
        ev0(end+1) = struct('time', 0, 'taskIdx', k, 'oldUAV', 0, 'newUAV', u_target, ...
            'trigger', 'initial', 'reason', 'BDTR-Initial'); %#ok<AGROW>
    end
end

% Set initial active task for each UAV
for i = 1:numel(uavs)
    if ~isempty(uavs(i).queue)
        uavs(i).assignedTask = uavs(i).queue(1);
    end
end
end

function [uavs, tasks, evRel] = bdtrAssignSingleTask(uavs, tasks, k, t)
evRel = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});
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
    loads = arrayfun(@(u) numel(u.queue), uavs(cand));
    minLoad = min(loads);
    candMin = cand(loads == minLoad);
    u_target = min(candMin);
    uavs(u_target).queue(end+1) = k;
    tasks(k).assignedUAV = u_target;
    tasks(k).status = 'assigned';
    if uavs(u_target).assignedTask == 0
        uavs(u_target).assignedTask = k;
    end
    evRel(end+1) = struct('time', t, 'taskIdx', k, 'oldUAV', 0, 'newUAV', u_target, ...
        'trigger', 'reactive', 'reason', 'BDTR-MidwayRelease'); %#ok<AGROW>
end
end

function [uavs, tasks, evBDTR] = bdtrReallocation(uavs, tasks, u_fail, t)
evBDTR = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});

% ------------------- PHASE 1: Feasibility Restoration -------------------
q_fail = uavs(u_fail).queue;
k_invalid = [];
for idx = 1:numel(q_fail)
    k = q_fail(idx);
    if ~isFeasible(tasks(k).requiredCap, uavs(u_fail).capabilities)
        k_invalid(end+1) = k; %#ok<AGROW>
    end
end

if ~isempty(k_invalid)
    priK = [tasks(k_invalid).priority];
    [~, ordK] = sortrows([-priK(:), k_invalid(:)]);
    k_invalid = k_invalid(ordK);

    uavs(u_fail).queue = setdiff(uavs(u_fail).queue, k_invalid, 'stable');
    if ismember(uavs(u_fail).assignedTask, k_invalid)
        tasks(uavs(u_fail).assignedTask).arrivalTime = NaN;
        if ~isempty(uavs(u_fail).queue)
            uavs(u_fail).assignedTask = uavs(u_fail).queue(1);
        else
            uavs(u_fail).assignedTask = 0;
        end
    end

    for idx = 1:numel(k_invalid)
        k = k_invalid(idx);
        tasks(k).arrivalTime = NaN;
        req = tasks(k).requiredCap;
        u_cand = [];
        for u = 1:numel(uavs)
            if isFeasible(req, uavs(u).capabilities)
                u_cand(end+1) = u; %#ok<AGROW>
            end
        end
        if ~isempty(u_cand)
            loads = arrayfun(@(u) numel(u.queue), uavs(u_cand));
            minLoad = min(loads);
            candMin = u_cand(loads == minLoad);
            u_target = min(candMin);

            uavs(u_target).queue(end+1) = k;
            tasks(k).assignedUAV = u_target;
            tasks(k).status = 'assigned';
            tasks(k).atriskReason = '';
            if uavs(u_target).assignedTask == 0
                uavs(u_target).assignedTask = k;
            end
            evBDTR(end+1) = struct('time', t, 'taskIdx', k, 'oldUAV', u_fail, 'newUAV', u_target, ...
                'trigger', 'reactive', 'reason', 'BDTR-Phase1-Offload'); %#ok<AGROW>
        else
            tasks(k).assignedUAV = 0;
            tasks(k).status = 'atrisk';
            tasks(k).atriskReason = 'Capability';
        end
    end
end

% ----------------- PHASE 2: Residual Capacity Exploitation -----------------
u_donor = setdiff(1:numel(uavs), u_fail);

while true
    if isempty(u_donor)
        break;
    end

    donor_loads = arrayfun(@(u) numel(u.queue), uavs(u_donor));
    maxLoad = max(donor_loads);
    candMax = u_donor(donor_loads == maxLoad);
    u_d = min(candMax);

    if (numel(uavs(u_d).queue) - numel(uavs(u_fail).queue)) <= 1
        break;
    end

    candTasks = uavs(u_d).queue;
    swappable = [];
    for qIdx = candTasks
        if isFeasible(tasks(qIdx).requiredCap, uavs(u_fail).capabilities)
            if qIdx == uavs(u_d).assignedTask && ~isnan(tasks(qIdx).arrivalTime) && (t - tasks(qIdx).arrivalTime) > 0
                continue;
            end
            swappable(end+1) = qIdx; %#ok<AGROW>
        end
    end

    if ~isempty(swappable)
        k_star = min(swappable);

        uavs(u_d).queue = uavs(u_d).queue(uavs(u_d).queue ~= k_star);
        if uavs(u_d).assignedTask == k_star
            if ~isempty(uavs(u_d).queue)
                uavs(u_d).assignedTask = uavs(u_d).queue(1);
            else
                uavs(u_d).assignedTask = 0;
            end
        end

        uavs(u_fail).queue(end+1) = k_star;
        if uavs(u_fail).assignedTask == 0
            uavs(u_fail).assignedTask = k_star;
        end
        tasks(k_star).assignedUAV = u_fail;
        tasks(k_star).status = 'assigned';
        tasks(k_star).atriskReason = '';
        tasks(k_star).arrivalTime = NaN;

        evBDTR(end+1) = struct('time', t, 'taskIdx', k_star, 'oldUAV', u_d, 'newUAV', u_fail, ...
            'trigger', 'reactive', 'reason', 'BDTR-Phase2-PullBack'); %#ok<AGROW>
    else
        u_donor = setdiff(u_donor, u_d);
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

function metrics = computeMissionMetrics(uavs, tasks, events, cfg) %#ok<INUSD>
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
end
