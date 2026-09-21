function result = sim(cfg, strategy, visualize)
% SIM  Run one full mission timeline under the SROM policy.
%
% Li et al. 2023, Algorithm 1 (RELIAB ENG SYST SAFE 237:109368):
%   binary platform failure, unidirectional offload of ALL remaining
%   missions, exhaustive permutation search onto spare-capacity survivors.

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'common'));

if nargin < 1 || isempty(cfg)
    cfg = common_config('srom');
end
if nargin < 2 || isempty(strategy)
    strategy = 'srom';
end
if nargin < 3
    visualize = cfg.sim.visualize;
end
if ~strcmp(strategy, 'srom')
    error('sim:unknownStrategy', 'Expected strategy "srom", got "%s".', strategy);
end

uavs  = makeFleet(cfg);
tasks = makeTaskSet(cfg);

events = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});

% ---- Initial allocation at t=0: SROM greedy-sort load-minimizing assignment ----
initTasks = find([tasks.releaseTime] <= 0);
pendingTasks = find([tasks.releaseTime] > 0);
for pIdx = pendingTasks
    tasks(pIdx).status = 'pending';
end

if ~isempty(initTasks)
    [uavs, tasks, ev0] = sromInitialAllocation(uavs, tasks, initTasks);
    events = [events, ev0];
end

if visualize
    rs = initRender(cfg, strategy);
end

for t = 0:cfg.sim.dt:cfg.sim.tEnd

    % ---- Dynamic Midway Task Release ----
    for j = 1:numel(tasks)
        if strcmp(tasks(j).status, 'pending') && t >= tasks(j).releaseTime
            [uavs, tasks, evRel] = sromAssignSingleTask(uavs, tasks, j, t, cfg);
            events = [events, evRel]; %#ok<AGROW>
        end
    end

    [uavs, justChanged, degradedUAVs, degradedCaps] = fireCapabilityChanges(uavs, cfg, t);

    % ---- Reactive trigger: on the tick capability loss lands, run SROM Algorithm 1
    if justChanged
        for dIdx = 1:numel(degradedUAVs)
            u_fail = degradedUAVs(dIdx);
            events(end+1) = struct('time', t, 'taskIdx', 0, 'oldUAV', 0, 'newUAV', u_fail, ...
                'trigger', 'degradation', 'reason', degradedCaps{dIdx}); %#ok<AGROW>
            [uavs, tasks, evSROM] = sromReallocation(uavs, tasks, u_fail, t, cfg);
            events = [events, evSROM]; %#ok<AGROW>
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

%% ======================= SROM ALGORITHM LOGIC =======================

function [uavs, tasks, ev0] = sromInitialAllocation(uavs, tasks, taskIndices)
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
        load_before = max(arrayfun(@(v) numel(v.queue), uavs));
        scores = zeros(1, numel(cand));
        for b = 1:numel(cand)
            u = cand(b);
            q_trial = numel(uavs(u).queue) + 1;
            other_u = setdiff(1:numel(uavs), u);
            other_loads = arrayfun(@(v) numel(v.queue), uavs(other_u));
            load_after = max([other_loads, q_trial]);
            scores(b) = load_before - load_after;
        end
        bestScore = max(scores);
        candBest = cand(scores == bestScore);
        loads = arrayfun(@(u) numel(u.queue), uavs(candBest));
        candMin = candBest(loads == min(loads));
        u_target = min(candMin);

        uavs(u_target).queue(end+1) = k;
        tasks(k).assignedUAV = u_target;
        tasks(k).status = 'assigned';
        ev0(end+1) = struct('time', 0, 'taskIdx', k, 'oldUAV', 0, 'newUAV', u_target, ...
            'trigger', 'initial', 'reason', 'SROM-Initial'); %#ok<AGROW>
    end
end

for i = 1:numel(uavs)
    if ~isempty(uavs(i).queue)
        uavs(i).assignedTask = uavs(i).queue(1);
    end
end
end

function [uavs, tasks, evRel] = sromAssignSingleTask(uavs, tasks, k, t, cfg)
evRel = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});
C = sromCapacity(cfg, numel(tasks), numel(uavs));
req = tasks(k).requiredCap;
cand = [];
for u = 1:numel(uavs)
    if isempty(uavs(u).capabilities)
        continue;
    end
    if numel(uavs(u).queue) >= C
        continue;
    end
    if isFeasible(req, uavs(u).capabilities)
        cand(end+1) = u; %#ok<AGROW>
    end
end
if isempty(cand)
    tasks(k).status = 'atrisk';
    tasks(k).atriskReason = 'Capability';
else
    loads = arrayfun(@(u) numel(u.queue), uavs(cand));
    candMin = cand(loads == min(loads));
    u_target = min(candMin);
    uavs(u_target).queue(end+1) = k;
    tasks(k).assignedUAV = u_target;
    tasks(k).status = 'assigned';
    if uavs(u_target).assignedTask == 0
        uavs(u_target).assignedTask = k;
    end
    evRel(end+1) = struct('time', t, 'taskIdx', k, 'oldUAV', 0, 'newUAV', u_target, ...
        'trigger', 'reactive', 'reason', 'SROM-MidwayRelease'); %#ok<AGROW>
end
end

function [uavs, tasks, evSROM] = sromReallocation(uavs, tasks, u_fail, t, cfg)
% Li et al. 2023 Algorithm 1 + Assumption 2 (Attack Condition) item 2.
evSROM = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});

C = sromCapacity(cfg, numel(tasks), numel(uavs));
uavs(u_fail).capabilities = {};

t_remain = uavs(u_fail).queue;
if isempty(t_remain)
    uavs(u_fail).assignedTask = 0;
    return;
end

for idx = 1:numel(t_remain)
    k = t_remain(idx);
    tasks(k).arrivalTime = NaN;
    tasks(k).assignedUAV = 0;
end
uavs(u_fail).queue = [];
uavs(u_fail).assignedTask = 0;

alive = [];
for u = 1:numel(uavs)
    if u ~= u_fail && ~isempty(uavs(u).capabilities)
        alive(end+1) = u; %#ok<AGROW>
    end
end

q_c = [];
for idx = 1:numel(alive)
    u = alive(idx);
    if numel(uavs(u).queue) < C
        q_c(end+1) = u; %#ok<AGROW>
    end
end

if isempty(q_c)
    for idx = 1:numel(t_remain)
        k = t_remain(idx);
        tasks(k).status = 'atrisk';
        tasks(k).atriskReason = 'Capability';
    end
    return;
end

mu = numel(t_remain);
nSlots = 0;
for h = 1:numel(q_c)
    nSlots = nSlots + max(0, C - numel(uavs(q_c(h)).queue));
end
P = sromPermutations(t_remain, tasks, nSlots, t);

nU = numel(uavs);
canDo = false(nU, numel(tasks));
for u = 1:nU
    if isempty(uavs(u).capabilities)
        continue;
    end
    for idx = 1:mu
        k = t_remain(idx);
        canDo(u, k) = isFeasible(tasks(k).requiredCap, uavs(u).capabilities);
    end
end

bestScore = -Inf;
bestAssign = zeros(1, numel(tasks));

for p = 1:size(P, 1)
    perm = P(p, :);
    qlen = zeros(1, numel(uavs));
    for u = 1:numel(uavs)
        qlen(u) = numel(uavs(u).queue);
    end
    assign = zeros(1, mu);
    score = 0;
    for g = 1:mu
        k = perm(g);
        bestU = 0;
        bestPhi = -Inf;
        for h = 1:numel(q_c)
            u = q_c(h);
            if qlen(u) >= C || ~canDo(u, k)
                continue;
            end
            phi = tasks(k).priority * 1000 + (C - qlen(u));
            if phi > bestPhi || (phi == bestPhi && (bestU == 0 || u < bestU))
                bestPhi = phi;
                bestU = u;
            end
        end
        if bestU > 0
            assign(g) = bestU;
            qlen(bestU) = qlen(bestU) + 1;
            score = score + bestPhi;
        end
    end
    if score > bestScore
        bestScore = score;
        bestAssign(:) = 0;
        for g = 1:mu
            bestAssign(perm(g)) = assign(g);
        end
    end
end

for idx = 1:numel(t_remain)
    k = t_remain(idx);
    u_target = 0;
    if k <= numel(bestAssign)
        u_target = bestAssign(k);
    end
    if u_target > 0
        uavs(u_target).queue(end+1) = k;
        if uavs(u_target).assignedTask == 0
            uavs(u_target).assignedTask = k;
        end
        tasks(k).assignedUAV = u_target;
        tasks(k).status = 'assigned';
        tasks(k).atriskReason = '';
        evSROM(end+1) = struct('time', t, 'taskIdx', k, 'oldUAV', u_fail, 'newUAV', u_target, ...
            'trigger', 'reactive', 'reason', 'SROM-Alg1'); %#ok<AGROW>
    else
        tasks(k).assignedUAV = 0;
        tasks(k).status = 'atrisk';
        tasks(k).atriskReason = 'Capability';
    end
end
end

function C = sromCapacity(cfg, nT, nU)
C = ceil(nT / max(1, nU));
if isfield(cfg, 'bdtr') && isfield(cfg.bdtr, 'nominalCapacity')
    C = cfg.bdtr.nominalCapacity;
end
end

function P = sromPermutations(t_remain, tasks, nSlots, t) %#ok<INUSD>
mu = numel(t_remain);
if mu <= 1
    P = t_remain(:).';
    return;
end
pri = [tasks(t_remain).priority];
[~, ord] = sortrows([-pri(:), t_remain(:)]);
ordered = t_remain(ord);
if nSlots >= mu
    P = ordered(:).';
    return;
end
maxExact = 7;
if mu <= maxExact
    P = perms(t_remain);
    return;
end
nSearch = min(mu, max(nSlots, 1));
nSearch = min(nSearch, maxExact);
head = ordered(1:nSearch);
tail = ordered(nSearch+1:end);
H = perms(head);
if isempty(tail)
    P = H;
else
    P = [H, repmat(tail, size(H, 1), 1)];
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
