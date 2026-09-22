function result = sim(cfg, strategy)
% SIM  State-Aware Bidirectional Reallocation (SABR), headless batch.
% Phase 1 is the Reactive Hungarian allocator (LAP + AtRisk preemption),
% unchanged. Phase 2 replaces BDTR's load-gap swap with a deadline-aware,
% capability-aware transfer gate.

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'common'));

if nargin < 1 || isempty(cfg)
    cfg = common_config('sabr');
end
if nargin < 2 || isempty(strategy)
    strategy = 'sabr';
end
if ~strcmp(strategy, 'sabr')
    error('sim:unknownStrategy', ...
        'Only "sabr" is supported in this method. Got "%s".', strategy);
end

uavs  = makeFleet(cfg);
tasks = makeTaskSet(cfg);

events = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});

% Initial allocation: assign all released tasks into UAV queues via multi-round LAP
initTasks = find([tasks.releaseTime] <= 0);
pendingTasks = find([tasks.releaseTime] > 0);
for pIdx = pendingTasks
    tasks(pIdx).status = 'pending';
end

unassignedInit = initTasks;
while ~isempty(unassignedInit)
    assignedBefore = find(strcmp({tasks.status}, 'assigned'));
    [uavs, tasks, ev0] = reallocationEvent(uavs, tasks, cfg, 0, unassignedInit);
    events = [events, ev0]; %#ok<AGROW>
    assignedAfter = find(strcmp({tasks.status}, 'assigned'));
    newlyAssigned = setdiff(assignedAfter, assignedBefore);
    if isempty(newlyAssigned)
        break; % Remaining tasks cannot be assigned to any capable UAV
    end
    unassignedInit = setdiff(unassignedInit, newlyAssigned);
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

    % ---- Reactive trigger on capability loss: mark invalid assignments as AtRisk & reallocate
    if justChanged
        for dIdx = 1:numel(degradedUAVs)
            events(end+1) = struct('time', t, 'taskIdx', 0, 'oldUAV', 0, 'newUAV', degradedUAVs(dIdx), ...
                'trigger', 'degradation', 'reason', degradedCaps{dIdx}); %#ok<AGROW>
        end
        [uavs, tasks] = markInfeasibleAssignedAsAtRisk(uavs, tasks);

        poolIdx = find(strcmp({tasks.status}, 'atrisk'));
        while ~isempty(poolIdx)
            assignedBefore = find(strcmp({tasks.status}, 'assigned'));
            [uavs, tasks, ev] = reallocationEvent(uavs, tasks, cfg, t, poolIdx);
            events = [events, ev]; %#ok<AGROW>
            assignedAfter = find(strcmp({tasks.status}, 'assigned'));
            newlyAssigned = setdiff(assignedAfter, assignedBefore);
            if isempty(newlyAssigned)
                break
            end
            poolIdx = setdiff(poolIdx, newlyAssigned);
        end
        [uavs, tasks, ev2] = sabrPhase2(uavs, tasks, cfg, t);
        events = [events, ev2]; %#ok<AGROW>
    end

    % ---- Deadline expiry sweep: fail any unfinished task past deadline
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

    % Dispatch idle UAVs to any 'unassigned' tasks still waiting
    idleUAVs    = find([uavs.assignedTask] == 0);
    queuedTasks = find(strcmp({tasks.status}, 'unassigned'));
    if ~isempty(idleUAVs) && ~isempty(queuedTasks)
        [uavs, tasks, ev] = reallocationEvent(uavs, tasks, cfg, t, queuedTasks, idleUAVs);
        events = [events, ev]; %#ok<AGROW>
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

%% ======================= SABR PHASE 2 =======================

function [uavs, tasks, evList] = sabrPhase2(uavs, tasks, cfg, t)
% Deadline-aware residual-capacity transfers.
% Hard gates: capability on the recipient's remaining payloads, the
% transferred task is not already executing, the task meets its deadline
% on the recipient, and no incumbent on the recipient is made newly late.
% Score: DeltaJ = w1*Resolved - w2*TransferCost - w3*DeltaLoadImbalance
% with w1 >> w2, w3. A transfer is committed only when DeltaJ > 0.
% Tie-break: lowest task index, then lowest donor, recipient, insert slot.

evList = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});

wResolved  = 10;
wTransfer  = 1;
wImbalance = 0.15;
nomCap = cfg.bdtr.nominalCapacity;
refTravel = cfg.cost.refDistance / cfg.cost.refSpeed;

nU = numel(uavs);
nT = numel(tasks);
locked = false(1, nT);
maxPasses = max(1, nT);

for pass = 1:maxPasses
    bestDJ  = 0;
    bestK   = inf;
    bestD   = inf;
    bestR   = inf;
    bestIns = inf;
    found   = false;

    baseComp = completionVector(uavs, tasks, t);
    baseLens = queueLengths(uavs);
    baseImb  = std(baseLens);

    for d = 1:nU
        qD = uavs(d).queue;
        if isempty(qD)
            continue
        end
        donorLate = false(1, numel(qD));
        for p = 1:numel(qD)
            k = qD(p);
            donorLate(p) = baseComp(k) > tasks(k).deadline;
        end
        downstreamLate = false(1, numel(qD));
        seen = false;
        for p = numel(qD):-1:1
            downstreamLate(p) = seen;
            seen = seen || donorLate(p);
        end

        for p = 1:numel(qD)
            k = qD(p);
            if locked(k) || ~strcmp(tasks(k).status, 'assigned')
                continue
            end
            if isTaskInProgress(tasks(k), k, uavs(d), t)
                continue
            end
            kLate = donorLate(p);
            blocksLate = downstreamLate(p);
            donorOverloaded = numel(qD) > nomCap;
            if ~(kLate || blocksLate || donorOverloaded)
                continue
            end

            for r = 1:nU
                if r == d
                    continue
                end
                if ~isFeasible(tasks(k).requiredCap, uavs(r).capabilities)
                    continue
                end
                % Residual-capacity recipient: strictly lighter, or able
                % to absorb a late task even at equal length.
                if numel(uavs(r).queue) > numel(qD)
                    continue
                end
                if ~kLate && ~blocksLate && numel(uavs(r).queue) + 1 >= numel(qD)
                    continue
                end

                insAppend = numel(uavs(r).queue) + 1;
                candIns = insAppend;
                insFront = frontInsertPos(uavs(r), tasks, t);
                if insFront ~= insAppend
                    candIns = [insFront, insAppend];
                end
                for ii = 1:numel(candIns)
                    ins = candIns(ii);
                    [nRes, transferCost, imbDelta, ok] = scoreTransfer( ...
                        uavs, tasks, t, k, d, r, ins, baseComp, baseImb, refTravel);
                    if ~ok
                        continue
                    end
                    relief = 0;
                    if nRes == 0 && donorOverloaded && numel(qD) >= numel(uavs(r).queue) + 2
                        relief = 0.2;
                    end
                    resolvedScore = nRes + relief;
                    dJ = wResolved * resolvedScore - wTransfer * transferCost - wImbalance * imbDelta;
                    if dJ <= 1e-9
                        continue
                    end
                    if isBetterCandidate(dJ, k, d, r, ins, bestDJ, bestK, bestD, bestR, bestIns)
                        bestDJ  = dJ;
                        bestK   = k;
                        bestD   = d;
                        bestR   = r;
                        bestIns = ins;
                        found   = true;
                    end
                end
            end
        end
    end

    if ~found
        break
    end

    [uavs, tasks] = commitTransfer(uavs, tasks, bestK, bestD, bestR, bestIns);
    locked(bestK) = true;
    evList(end+1) = struct('time', t, 'taskIdx', bestK, 'oldUAV', bestD, ...
        'newUAV', bestR, 'trigger', 'reactive', 'reason', 'SABR-Phase2'); %#ok<AGROW>
end
end

function [nRes, transferCost, imbDelta, ok] = scoreTransfer(uavs, tasks, t, k, d, r, ins, baseComp, baseImb, refTravel)
nRes = 0;
transferCost = inf;
imbDelta = 0;
ok = false;

tasksLocal = tasks;
tasksLocal(k).arrivalTime = NaN;

qD = uavs(d).queue(uavs(d).queue ~= k);
qR = insertedQueue(uavs(r).queue, k, ins);
uD = retarget(uavs(d), qD);
uR = retarget(uavs(r), qR);

afterComp = baseComp;
oldIds = [uavs(d).queue, uavs(r).queue];
afterComp(oldIds) = inf;
afterComp = writeQueueComp(afterComp, uD, tasksLocal, t);
afterComp = writeQueueComp(afterComp, uR, tasksLocal, t);
if ~isfinite(afterComp(k)) || afterComp(k) > tasks(k).deadline
    return
end

involved = unique([k, uavs(d).queue, uavs(r).queue]);
nNewMiss = 0;
for ii = 1:numel(involved)
    j = involved(ii);
    wasLate = baseComp(j) > tasks(j).deadline;
    nowLate = afterComp(j) > tasks(j).deadline;
    if wasLate && ~nowLate
        nRes = nRes + tasks(j).priority;
    elseif ~wasLate && nowLate
        nNewMiss = nNewMiss + 1;
    end
end
if nNewMiss > 0
    return
end

travel = norm(tasks(k).location - uavs(r).position) / max(uavs(r).speed, eps);
transferCost = travel / max(refTravel, eps);

lens = queueLengths(uavs);
lens(d) = max(0, lens(d) - 1);
lens(r) = lens(r) + 1;
imbDelta = std(lens) - baseImb;
ok = true;
end

function better = isBetterCandidate(dJ, k, d, r, ins, bestDJ, bestK, bestD, bestR, bestIns)
if dJ > bestDJ + 1e-9
    better = true;
    return
end
if dJ < bestDJ - 1e-9
    better = false;
    return
end
better = false;
if k < bestK
    better = true;
elseif k == bestK && d < bestD
    better = true;
elseif k == bestK && d == bestD && r < bestR
    better = true;
elseif k == bestK && d == bestD && r == bestR && ins < bestIns
    better = true;
end
end

function ins = frontInsertPos(uav, tasks, t)
q = uav.queue;
if isempty(q)
    ins = 1;
    return
end
if isTaskInProgress(tasks(q(1)), q(1), uav, t)
    ins = min(2, numel(q) + 1);
else
    ins = 1;
end
end

function comp = writeQueueComp(comp, uav, tasks, t)
q = uav.queue;
if isempty(q)
    return
end
pos = uav.position;
clock = t;
for p = 1:numel(q)
    k = q(p);
    if p == 1 && uav.assignedTask == k && ~isnan(tasks(k).arrivalTime)
        elapsed = max(0, t - tasks(k).arrivalTime);
        clock = t + max(0, tasks(k).execTime - elapsed);
        pos = tasks(k).location;
    else
        travel = norm(tasks(k).location - pos) / max(uav.speed, eps);
        clock = clock + travel + tasks(k).execTime;
        pos = tasks(k).location;
    end
    comp(k) = clock;
end
end

function tf = isTaskInProgress(task, k, uav, t)
tf = (uav.assignedTask == k) && ~isnan(task.arrivalTime) && ((t - task.arrivalTime) > 0);
end

function qNew = insertedQueue(q, k, insPos)
q = q(q ~= k);
if isempty(q)
    qNew = k;
    return
end
if insPos <= 1
    qNew = [k, q];
elseif insPos > numel(q)
    qNew = [q, k];
else
    qNew = [q(1:insPos-1), k, q(insPos:end)];
end
end

function u = retarget(u, q)
u.queue = q;
if isempty(q)
    u.assignedTask = 0;
else
    u.assignedTask = q(1);
end
end

function [uavs, tasks] = commitTransfer(uavs, tasks, k, d, r, insPos)
uavs(d).queue = uavs(d).queue(uavs(d).queue ~= k);
if uavs(d).assignedTask == k
    if isempty(uavs(d).queue)
        uavs(d).assignedTask = 0;
    else
        uavs(d).assignedTask = uavs(d).queue(1);
    end
end
uavs(r).queue = insertedQueue(uavs(r).queue, k, insPos);
if insPos <= 1 || uavs(r).assignedTask == 0
    uavs(r).assignedTask = uavs(r).queue(1);
end
tasks(k).assignedUAV = r;
tasks(k).status = 'assigned';
tasks(k).atriskReason = '';
tasks(k).arrivalTime = NaN;
end

function comp = completionVector(uavs, tasks, t)
nT = numel(tasks);
comp = inf(1, nT);
for i = 1:numel(uavs)
    q = uavs(i).queue;
    if isempty(q)
        continue
    end
    pos = uavs(i).position;
    clock = t;
    for p = 1:numel(q)
        k = q(p);
        if p == 1 && uavs(i).assignedTask == k && ~isnan(tasks(k).arrivalTime)
            elapsed = max(0, t - tasks(k).arrivalTime);
            clock = t + max(0, tasks(k).execTime - elapsed);
            pos = tasks(k).location;
        else
            travel = norm(tasks(k).location - pos) / max(uavs(i).speed, eps);
            clock = clock + travel + tasks(k).execTime;
            pos = tasks(k).location;
        end
        comp(k) = clock;
    end
end
end

function lens = queueLengths(uavs)
lens = zeros(1, numel(uavs));
for i = 1:numel(uavs)
    lens(i) = numel(uavs(i).queue);
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
metrics.phase2Count       = sum(strcmp({events.reason}, 'SABR-Phase2'));

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
