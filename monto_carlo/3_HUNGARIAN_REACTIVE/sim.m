function result = sim(cfg, strategy, visualize)
% SIM  Run one full mission timeline under the Reactive Hungarian policy.
% strategy: 'reactive' (Section 3 of BDTR_Baseline_Methods.md)
%
% Implements Algorithm 2 (Reactive Hungarian LAP Solver) plus the full
% AtRisk + priority-preemption pipeline from Section 3.3:
%   1. Snapshot fleet/task state at event start
%   2. Pool = newly-released unassigned tasks + all persistent AtRisk tasks
%   3. Snapshot-based F_j(t) and C_ij(t) for pool tasks
%   4. Solve joint LAP (Hungarian) with dummy-cost padding
%   5. Classify outcomes: real match -> Assigned, dummy match -> AtRisk
%   6. Sequential preemption phase (descending priority order)
%   7. Finalize / log
%
% STRUCTURAL PARITY: Uses multi-task .queue model (same as RRAM/SROM/BDTR)
% so all methods operate under the same capacity model for fair comparison.

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'common'));

if nargin < 1 || isempty(cfg)
    cfg = common_config('reactive');
end
if nargin < 2 || isempty(strategy)
    strategy = 'reactive';
end
if nargin < 3
    visualize = cfg.sim.visualize;
end
if ~strcmp(strategy, 'reactive')
    error('sim:unknownStrategy', ...
        'Only "reactive" is supported in this baseline. Got "%s".', strategy);
end

uavs  = makeFleet(cfg);
tasks = makeTaskSet(cfg);

events = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});

% Initial allocation: one reallocation event at t=0 over tasks released at t=0.
initTasks = find([tasks.releaseTime] <= 0);
pendingTasks = find([tasks.releaseTime] > 0);
for pIdx = pendingTasks
    tasks(pIdx).status = 'pending';
end
if ~isempty(initTasks)
    [uavs, tasks, ev0] = reallocationEvent(uavs, tasks, cfg, 0, initTasks);
    events = [events, ev0];
end

if visualize
    rs = initRender(cfg, strategy);
end

for t = 0:cfg.sim.dt:cfg.sim.tEnd

    % ---- Dynamic Midway Task Release ----
    for j = 1:numel(tasks)
        if strcmp(tasks(j).status, 'pending') && t >= tasks(j).releaseTime
            tasks(j).status = 'unassigned';
            events(end+1) = struct('time', t, 'taskIdx', j, 'oldUAV', 0, 'newUAV', 0, ...
                'trigger', 'reactive', 'reason', 'NewTaskReleased'); %#ok<AGROW>
        end
    end

    [uavs, justChanged, degradedUAVs, degradedCaps] = fireCapabilityChanges(uavs, cfg, t);

    % ---- Reactive trigger on capability loss: mark invalid assignments as AtRisk
    if justChanged
        for dIdx = 1:numel(degradedUAVs)
            events(end+1) = struct('time', t, 'taskIdx', 0, 'oldUAV', 0, 'newUAV', degradedUAVs(dIdx), ...
                'trigger', 'degradation', 'reason', degradedCaps{dIdx}); %#ok<AGROW>
        end
        [uavs, tasks] = markInfeasibleAssignedAsAtRisk(uavs, tasks);
    end

    % ---- Deadline expiry sweep: fail any unassigned/atrisk/assigned task past deadline
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

    % ---- Build the pool for this event: AtRisk tasks
    poolIdx = find(strcmp({tasks.status}, 'atrisk'));

    if ~isempty(poolIdx)
        [uavs, tasks, ev] = reallocationEvent(uavs, tasks, cfg, t, poolIdx);
        events = [events, ev]; %#ok<AGROW>
    end

    [uavs, tasks] = moveFleet(uavs, tasks, t, cfg.sim.dt);

    % Dispatch idle UAVs to any 'unassigned' tasks still waiting
    idleUAVs    = find([uavs.assignedTask] == 0);
    queuedTasks = find(strcmp({tasks.status}, 'unassigned'));
    if ~isempty(idleUAVs) && ~isempty(queuedTasks)
        [uavs, tasks, ev] = reallocationEvent(uavs, tasks, cfg, t, queuedTasks, idleUAVs);
        events = [events, ev]; %#ok<AGROW>
    end

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

%% ======================= HUNGARIAN & PREEMPTION LOGIC =======================

function T = estCompletionTime(t, uavPosition, uavSpeed, taskLocation, taskExecTime, uavQueueLen)
travelTime = norm(taskLocation - uavPosition) / uavSpeed;
queueWait  = uavQueueLen * taskExecTime;
T = t + travelTime + queueWait + taskExecTime;
end

function cost = costFunction(t, uav, task, isCurrentlyAssignedToThisUAV, cfg)
dist = norm(task.location - uav.position);
c_dist = (dist / uav.speed) / (cfg.cost.refDistance / cfg.cost.refSpeed);

% Use queue length for workload (structural parity with other methods)
queueLen = numel(uav.queue);
if isCurrentlyAssignedToThisUAV
    queueLen = max(0, queueLen - 1); % don''t double-count the task itself
end
c_workload = (queueLen * task.execTime) / (cfg.cost.refQueueLen * cfg.cost.refExecTime);

T_ij = estCompletionTime(t, uav.position, uav.speed, task.location, task.execTime, queueLen);
c_comp = (T_ij - t) / task.deadline;

disruption = 0;
if isCurrentlyAssignedToThisUAV
    disruption = -cfg.cost.disruptionPenalty;
end

cost = cfg.cost.wDistance    * c_dist     + ...
       cfg.cost.wWorkload    * c_workload + ...
       cfg.cost.wCompletion  * c_comp     + ...
       disruption;
end

function [uavs, tasks, evList] = reallocationEvent(uavs, tasks, cfg, t, poolTaskIdx, candidateUavIdx)
evList = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});

if isempty(poolTaskIdx)
    return
end
if nargin < 6 || isempty(candidateUavIdx)
    candidateUavIdx = 1:numel(uavs);
end

nT = numel(poolTaskIdx);
nU = numel(candidateUavIdx);
N  = max(nT, nU);

costMat = fill(cfg.cost.dummyCost, N, N);

for r = 1:nT
    j = poolTaskIdx(r);
    for c = 1:nU
        i = candidateUavIdx(c);
        if ~isFeasible(tasks(j).requiredCap, uavs(i).capabilities)
            continue
        end
        isAssigned = (tasks(j).assignedUAV == i);
        costMat(r, c) = costFunction(t, uavs(i), tasks(j), isAssigned, cfg);
    end
end

assignment = solveLAP(costMat);

assignedPoolTasks = [];
for r = 1:nT
    c = assignment(r);
    j = poolTaskIdx(r);
    if c <= nU && costMat(r, c) < (cfg.cost.dummyCost - 1)
        i = candidateUavIdx(c);
        oldUAV = tasks(j).assignedUAV;
        [uavs, tasks] = doCommit(uavs, tasks, j, i);
        evList(end+1) = struct('time', t, 'taskIdx', j, 'oldUAV', oldUAV, 'newUAV', i, ...
            'trigger', 'reactive', 'reason', 'LAP'); %#ok<AGROW>
        assignedPoolTasks(end+1) = j; %#ok<AGROW>
    else
        tasks(j) = setAtRisk(tasks(j), classifyAtRiskReason(tasks(j), uavs, candidateUavIdx, nT, assignment(r), costMat));
    end
end

% Preemption phase
unassignedPoolTasks = setdiff(poolTaskIdx, assignedPoolTasks);
if ~isempty(unassignedPoolTasks)
    priorities = [tasks(unassignedPoolTasks).priority];
    [~, pOrd] = sortrows([-priorities(:), unassignedPoolTasks(:)]);
    sortedUnassigned = unassignedPoolTasks(pOrd);

    uavCommittedThisPhase = false(1, numel(uavs));
    for jA = sortedUnassigned
        pA = tasks(jA).priority;
        locA = tasks(jA).location;
        exA  = tasks(jA).execTime;

        bestU = 0;
        bestPreemptCost = Inf;
        bestDisplacedTask = 0;

        for i = 1:numel(uavs)
            if uavCommittedThisPhase(i)
                continue
            end
            if ~isFeasible(tasks(jA).requiredCap, uavs(i).capabilities)
                continue
            end
            jB = uavs(i).assignedTask;
            if jB == 0
                continue
            end
            if ~strcmp(tasks(jB).status, 'assigned')
                continue
            end
            if ~isnan(tasks(jB).arrivalTime) && (t - tasks(jB).arrivalTime) > 0
                continue
            end
            if pA <= tasks(jB).priority
                continue
            end
            if ~displacedTaskHasSafeAlternative(jB, i, uavs, tasks, cfg, t, uavCommittedThisPhase)
                continue
            end
            TA = estCompletionTime(t, uavs(i).position, uavs(i).speed, locA, exA, 0);
            if TA > tasks(jA).deadline
                continue
            end
            c_cand = costFunction(t, uavs(i), tasks(jA), false, cfg);
            if c_cand < bestPreemptCost
                bestPreemptCost = c_cand;
                bestU = i;
                bestDisplacedTask = jB;
            end
        end

        if bestU ~= 0
            uA = bestU;
            jB = bestDisplacedTask;
            oldUA = tasks(jA).assignedUAV;

            [uavs, tasks] = doCommit(uavs, tasks, jA, uA);
            uavCommittedThisPhase(uA) = true;

            tasks(jB) = setAtRisk(tasks(jB), 'Displaced');
            tasks(jB).assignedUAV = 0;
            % Remove displaced task from any queue it''s in
            for qi = 1:numel(uavs)
                uavs(qi).queue = uavs(qi).queue(uavs(qi).queue ~= jB);
            end

            evList(end+1) = struct('time', t, 'taskIdx', jA, 'oldUAV', oldUA, 'newUAV', uA, ...
                'trigger', 'reactive-preempt', 'reason', sprintf('Preempted_T%d', jB)); %#ok<AGROW>
            evList(end+1) = struct('time', t, 'taskIdx', jB, 'oldUAV', uA, 'newUAV', 0, ...
                'trigger', 'reactive-preempt', 'reason', 'Displaced'); %#ok<AGROW>
        end
    end
end
end

function mat = fill(val, m, n)
mat = val * ones(m, n);
end

function assignment = solveLAP(costMatrix)
if exist('matchpairs', 'file') == 2
    M = matchpairs(costMatrix, 1e9);
    assignment = zeros(size(costMatrix, 1), 1);
    for k = 1:size(M, 1)
        assignment(M(k, 1)) = M(k, 2);
    end
else
    assignment = munkresSimple(costMatrix);
end
end

function assignment = munkresSimple(C)
[nRows, nCols] = size(C);
assignment = zeros(nRows, 1);
usedCols = false(1, nCols);

for r = 1:nRows
    rowVals = C(r, :);
    rowVals(usedCols) = Inf;
    [minV, bestC] = min(rowVals);
    if isfinite(minV)
        assignment(r) = bestC;
        usedCols(bestC) = true;
    end
end
end

function [uavs, tasks] = doCommit(uavs, tasks, j, i)
% Queue-based commit (structural parity with RRAM/SROM/BDTR):
% Append task j to UAV i's queue; set as active if queue was empty.

% Remove task j from any other UAV's queue first
oldUAV = tasks(j).assignedUAV;
if oldUAV > 0 && oldUAV <= numel(uavs) && oldUAV ~= i
    uavs(oldUAV).queue = uavs(oldUAV).queue(uavs(oldUAV).queue ~= j);
    if uavs(oldUAV).assignedTask == j
        if ~isempty(uavs(oldUAV).queue)
            uavs(oldUAV).assignedTask = uavs(oldUAV).queue(1);
        else
            uavs(oldUAV).assignedTask = 0;
        end
    end
end

% Add to new UAV''s queue if not already there
if ~ismember(j, uavs(i).queue)
    uavs(i).queue(end+1) = j;
end
if uavs(i).assignedTask == 0
    uavs(i).assignedTask = uavs(i).queue(1);
end
tasks(j).assignedUAV = i;
tasks(j).status = 'assigned';
tasks(j).atriskReason = '';
end

function task = setAtRisk(task, reason)
task.status = 'atrisk';
task.atriskReason = reason;
end

function reason = classifyAtRiskReason(task, uavs, candidateUavIdx, nT, a, costMat) %#ok<INUSD>
anyCapable = false;
for i = candidateUavIdx
    if isFeasible(task.requiredCap, uavs(i).capabilities)
        anyCapable = true;
        break
    end
end
if ~anyCapable
    reason = 'Capability';
else
    reason = 'SlotContested';
end
end

function [uavs, tasks] = markInfeasibleAssignedAsAtRisk(uavs, tasks)
for j = 1:numel(tasks)
    if ~strcmp(tasks(j).status, 'assigned')
        continue
    end
    i = tasks(j).assignedUAV;
    if i > 0 && i <= numel(uavs) && ~isFeasible(tasks(j).requiredCap, uavs(i).capabilities)
        % Remove from queue
        uavs(i).queue = uavs(i).queue(uavs(i).queue ~= j);
        if uavs(i).assignedTask == j
            if ~isempty(uavs(i).queue)
                uavs(i).assignedTask = uavs(i).queue(1);
            else
                uavs(i).assignedTask = 0;
            end
        end
        tasks(j).assignedUAV = 0;
        tasks(j) = setAtRisk(tasks(j), 'Capability');
    end
end
end

function safe = displacedTaskHasSafeAlternative(B, uA, uavs, tasks, ~, t, uavCommittedThisPhase)
safe = false;
for k = 1:numel(uavs)
    if k == uA || uavCommittedThisPhase(k)
        continue
    end
    if ~isFeasible(tasks(B).requiredCap, uavs(k).capabilities)
        continue
    end
    queueLen = numel(uavs(k).queue);
    Tk = estCompletionTime(t, uavs(k).position, uavs(k).speed, tasks(B).location, tasks(B).execTime, queueLen);
    if Tk <= tasks(B).deadline
        safe = true;
        return
    end
end
end

%% ======================= STATE CONSTRUCTION =======================

function uavs = makeFleet(cfg)
n = numel(cfg.uav);
% Structural parity: includes .queue field (same as RRAM/SROM/BDTR)
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
        % Check if there are queued tasks to activate
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
            continue;
        end
        if isnan(tasks(j).arrivalTime)
            tasks(j).arrivalTime = t;
        end
        if (t - tasks(j).arrivalTime) >= tasks(j).execTime
            tasks(j).status = 'complete';
            tasks(j).completeTime = t;
            % Remove from queue, advance to next
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
