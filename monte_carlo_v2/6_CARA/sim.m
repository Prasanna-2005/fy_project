function result = sim(cfg, strategy)
% SIM  CARA: Capability-Aware Reallocation (headless batch).
%
% Practical reallocation for a ground station, not a global queue solver.
% A task moves only when it is illegal, newly released, or already
% predicted late. Work the aircraft will reach before a command can
% return stays on that aircraft. An illegal task inside that window
% is dropped and is not given to anyone else.
%
% Nominal constants: tau_link = 0.5 s, tau_cpu = 0.05 s, so
% T_c = 1.05 s; chi = 30 s; heartbeat T_h = 5 s; late cap = N.
% The 50 ms compiled budget is not used as a wall-clock kill in this
% interpreter. Rounds stop when a round places nothing or the churn
% cap |D|+N is hit. Measured planning time is reported separately.

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'common'));

if nargin < 1 || isempty(cfg)
    cfg = common_config('cara');
end
if nargin < 2 || isempty(strategy)
    strategy = 'cara';
end
if ~strcmp(strategy, 'cara')
    error('sim:unknownStrategy', 'Expected strategy "cara", got "%s".', strategy);
end

pol = caraPolicy(cfg);
uavs  = makeFleet(cfg);
tasks = makeTaskSet(cfg);
events = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});
repairMs = [];

for j = 1:numel(tasks)
    if tasks(j).releaseTime > 0
        tasks(j).status = 'pending';
    end
end

[uavs, tasks, ev0, ms0] = cara(uavs, tasks, 0, cfg, pol, true);
events = [events, ev0]; %#ok<AGROW>
repairMs(end+1) = ms0; %#ok<AGROW>
nextBeat = pol.Th;

for t = 0:cfg.sim.dt:cfg.sim.tEnd
    releasedNow = [];
    for j = 1:numel(tasks)
        if strcmp(tasks(j).status, 'pending') && t >= tasks(j).releaseTime
            tasks(j).status = 'unassigned';
            tasks(j).assignedUAV = 0;
            releasedNow(end+1) = j; %#ok<AGROW>
            events(end+1) = struct('time', t, 'taskIdx', j, 'oldUAV', 0, 'newUAV', 0, ...
                'trigger', 'release', 'reason', 'NewTaskReleased'); %#ok<AGROW>
        end
    end

    [uavs, justChanged, degradedUAVs, degradedCaps] = fireCapabilityChanges(uavs, cfg, t);
    if justChanged
        for dIdx = 1:numel(degradedUAVs)
            events(end+1) = struct('time', t, 'taskIdx', 0, 'oldUAV', 0, 'newUAV', degradedUAVs(dIdx), ...
                'trigger', 'degradation', 'reason', degradedCaps{dIdx}); %#ok<AGROW>
        end
    end

    heartbeat = (t + 1e-9 >= nextBeat) && anyFreeLate(uavs, tasks, t, cfg, t + pol.Tc);
    if justChanged || ~isempty(releasedNow) || heartbeat
        [uavs, tasks, ev, ms] = cara(uavs, tasks, t, cfg, pol, false);
        events = [events, ev]; %#ok<AGROW>
        repairMs(end+1) = ms; %#ok<AGROW>
        nextBeat = t + pol.Th;
    end

    for j = 1:numel(tasks)
        if ~strcmp(tasks(j).status, 'complete') && ~strcmp(tasks(j).status, 'failed') && ~strcmp(tasks(j).status, 'pending')
            if t >= tasks(j).deadline
                tasks(j).status = 'failed';
                i = tasks(j).assignedUAV;
                if i > 0 && i <= numel(uavs)
                    uavs(i).queue = asRow(uavs(i).queue);
                    uavs(i).queue = uavs(i).queue(uavs(i).queue ~= j);
                end
            end
        end
    end
    uavs = refreshHeads(uavs);

    [uavs, tasks] = moveFleet(uavs, tasks, t, cfg.sim.dt, cfg);
end

result.uavs     = uavs;
result.tasks    = tasks;
result.events   = events;
result.metrics  = computeMissionMetrics(uavs, tasks, events, cfg);
result.strategy = strategy;
result.repairMs = repairMs;
if isempty(repairMs)
    result.metrics.medianRepairMs = 0;
    result.metrics.p95RepairMs = 0;
else
    result.metrics.medianRepairMs = median(repairMs);
    result.metrics.p95RepairMs = percentile95(repairMs);
end
result.metrics.frozenLost = sum(strcmp({events.reason}, 'CARA-FrozenLost'));
result.metrics.unsaved    = sum(strcmp({events.reason}, 'CARA-Unsaved'));
end

%% ======================= POLICY =======================

function pol = caraPolicy(cfg)
pol.chi = 30;
pol.tauLink = 0.5;
pol.tauCpu = 0.05;
pol.Th = 5;
pol.lateCap = [];
pol.unmatchedCost = 5e5;
pol.lastResortBase = 1e5;
if isfield(cfg, 'cara')
    c = cfg.cara;
    if isfield(c, 'chi') && ~isempty(c.chi), pol.chi = c.chi; end
    if isfield(c, 'tauLink') && ~isempty(c.tauLink), pol.tauLink = c.tauLink; end
    if isfield(c, 'tauCpu') && ~isempty(c.tauCpu), pol.tauCpu = c.tauCpu; end
    if isfield(c, 'Th') && ~isempty(c.Th), pol.Th = c.Th; end
    if isfield(c, 'lateCap') && ~isempty(c.lateCap), pol.lateCap = c.lateCap; end
end
pol.Tc = 2 * pol.tauLink + pol.tauCpu;
end

%% ======================= CARA =======================

function [uavs, tasks, ev, ms] = cara(uavs, tasks, t, cfg, pol, isLaunch)
t0 = tic;
ev = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});
nU = numel(uavs);
if isempty(pol.lateCap)
    lateCap = nU;
else
    lateCap = pol.lateCap;
end
if isLaunch
    lockTime = t + pol.Tc;
    readyFloor = -inf;
else
    lockTime = t + pol.Tc;
    readyFloor = t + pol.Tc;
end

[uavs, tasks, evDrop] = dropFrozenIllegal(uavs, tasks, t, cfg, lockTime);
ev = [ev, evDrop]; %#ok<AGROW>

[uavs, tasks, illegal] = takeFreeIllegal(uavs, tasks, t, cfg, lockTime);
unassigned = find(strcmp({tasks.status}, 'unassigned'));
must = unique([illegal, unassigned], 'stable');
latePool = lateCandidates(uavs, tasks, t, cfg, lockTime, lateCap);
% A task already in the must-place pool is not also a late move.
latePool = setdiff(latePool, must, 'stable');

D = unique([must, latePool], 'stable');
cap = numel(D) + nU;

[uavs, tasks, ev1, n1] = assignPool(uavs, tasks, must, t, cfg, pol, lockTime, readyFloor, true, cap);
ev = [ev, ev1]; %#ok<AGROW>
[uavs, tasks, ev2, ~] = assignPool(uavs, tasks, latePool, t, cfg, pol, lockTime, readyFloor, false, cap - n1);
ev = [ev, ev2]; %#ok<AGROW>

for j = illegal
    if ~strcmp(tasks(j).status, 'assigned') || ~hostCanDo(uavs, tasks, j)
        old = tasks(j).assignedUAV;
        uavs = stripTask(uavs, j);
        tasks(j).status = 'failed';
        tasks(j).atriskReason = 'Unsaved';
        tasks(j).assignedUAV = 0;
        tasks(j).arrivalTime = NaN;
        tasks(j).onStationUAV = 0;
        ev(end+1) = struct('time', t, 'taskIdx', j, 'oldUAV', old, 'newUAV', 0, ...
            'trigger', 'cara-drop', 'reason', 'CARA-Unsaved'); %#ok<AGROW>
    end
end
ms = toc(t0) * 1000;
end

function [uavs, tasks, ev] = dropFrozenIllegal(uavs, tasks, t, cfg, lockTime)
ev = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});
changed = true;
while changed
    changed = false;
    for i = 1:numel(uavs)
        q = asRow(uavs(i).queue);
        if isempty(q)
            continue
        end
        f = frozenPrefixLength(uavs(i), tasks, q, t, cfg, lockTime, i);
        drop = [];
        for p = 1:f
            j = q(p);
            if ~isFeasible(tasks(j).requiredCap, uavs(i).capabilities)
                drop(end+1) = j; %#ok<AGROW>
            end
        end
        if isempty(drop)
            continue
        end
        changed = true;
        for j = drop
            uavs = stripTask(uavs, j);
            tasks(j).status = 'failed';
            tasks(j).atriskReason = 'FrozenLost';
            tasks(j).assignedUAV = 0;
            tasks(j).arrivalTime = NaN;
            tasks(j).onStationUAV = 0;
            ev(end+1) = struct('time', t, 'taskIdx', j, 'oldUAV', i, 'newUAV', 0, ...
                'trigger', 'cara-drop', 'reason', 'CARA-FrozenLost'); %#ok<AGROW>
        end
    end
end
end

function [uavs, tasks, illegal] = takeFreeIllegal(uavs, tasks, t, cfg, lockTime)
illegal = [];
for i = 1:numel(uavs)
    q = asRow(uavs(i).queue);
    if isempty(q)
        continue
    end
    f = frozenPrefixLength(uavs(i), tasks, q, t, cfg, lockTime, i);
    moving = [];
    for p = (f + 1):numel(q)
        j = q(p);
        if ~isFeasible(tasks(j).requiredCap, uavs(i).capabilities)
            moving(end+1) = j; %#ok<AGROW>
        end
    end
    for j = moving
        uavs = stripTask(uavs, j);
        tasks(j).status = 'atrisk';
        tasks(j).atriskReason = 'Capability';
        tasks(j).assignedUAV = i;
        tasks(j).arrivalTime = NaN;
        tasks(j).onStationUAV = 0;
        illegal(end+1) = j; %#ok<AGROW>
    end
end
end

function pool = lateCandidates(uavs, tasks, t, cfg, lockTime, lateCap)
cands = [];
tards = [];
for i = 1:numel(uavs)
    q = asRow(uavs(i).queue);
    if isempty(q)
        continue
    end
    f = frozenPrefixLength(uavs(i), tasks, q, t, cfg, lockTime, i);
    [~, fin] = walkQueue(uavs(i), tasks, q, t, cfg, i, 0, -inf);
    for p = (f + 1):numel(q)
        j = q(p);
        late = fin(p) - tasks(j).deadline;
        if late > 1e-6 && isFeasible(tasks(j).requiredCap, uavs(i).capabilities)
            cands(end+1) = j; %#ok<AGROW>
            tards(end+1) = late; %#ok<AGROW>
        end
    end
end
pool = [];
if isempty(cands) || lateCap <= 0
    return
end
[~, ord] = sortrows([-tards(:), cands(:)]);
nTake = min(lateCap, numel(cands));
pool = cands(ord(1:nTake));
end

function [uavs, tasks, ev, nMove] = assignPool(uavs, tasks, pool, t, cfg, pol, lockTime, readyFloor, mustPlace, cap)
ev = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});
nMove = 0;
pool = unique(asRow(pool), 'stable');
if isempty(pool) || cap <= 0
    return
end
locked = false(1, numel(tasks));
nU = numel(uavs);
roundGuard = 0;
while nMove < cap && roundGuard <= numel(pool)
    roundGuard = roundGuard + 1;
    open = pool(~locked(pool));
    keep = false(size(open));
    for r = 1:numel(open)
        keep(r) = isMovableStatus(tasks(open(r)));
    end
    open = open(keep);
    if isempty(open)
        break
    end
    nO = numel(open);
    C = 1e9 * ones(nO, nU);
    for r = 1:nO
        j = open(r);
        for u = 1:nU
            [c, ~] = bestBid(uavs, tasks, j, u, t, cfg, pol, lockTime, readyFloor, mustPlace);
            if isfinite(c)
                C(r, u) = c + 1e-8 * j + 1e-10 * u + 1e-12 * j * u;
            end
        end
    end
    if all(C(:) >= pol.unmatchedCost)
        break
    end
    asg = solveLAP(C, pol.unmatchedCost);
    pairs = zeros(0, 2);
    for r = 1:nO
        u = asg(r);
        if u >= 1 && u <= nU && C(r, u) < pol.unmatchedCost
            pairs(end+1, :) = [open(r), u]; %#ok<AGROW>
        end
    end
    if isempty(pairs)
        break
    end
    pairs = sortrows(pairs, 1);
    movedThis = 0;
    for p = 1:size(pairs, 1)
        if nMove >= cap
            break
        end
        j = pairs(p, 1);
        u = pairs(p, 2);
        if locked(j) || ~isMovableStatus(tasks(j))
            continue
        end
        [c, slot] = bestBid(uavs, tasks, j, u, t, cfg, pol, lockTime, readyFloor, mustPlace);
        if ~isfinite(c)
            if ~mustPlace
                locked(j) = true;
            end
            continue
        end
        old = tasks(j).assignedUAV;
        [uavs, tasks] = commitMove(uavs, tasks, j, u, slot, t, cfg, lockTime, readyFloor);
        locked(j) = true;
        nMove = nMove + 1;
        movedThis = movedThis + 1;
        ev(end+1) = struct('time', t, 'taskIdx', j, 'oldUAV', old, 'newUAV', u, ...
            'trigger', 'reactive', 'reason', 'CARA'); %#ok<AGROW>
    end
    if movedThis == 0
        break
    end
end
end

function [cost, slot] = bestBid(uavs, tasks, k, u, t, cfg, pol, lockTime, readyFloor, mustPlace)
cost = inf;
slot = 1;
if ~isFeasible(tasks(k).requiredCap, uavs(u).capabilities)
    return
end
uCur = tasks(k).assignedUAV;
chi = pol.chi;
if uCur > 0 && u == uCur
    chi = 0;
end
orig = asRow(uavs(u).queue);
baseQ = orig(orig ~= k);
f = frozenPrefixLength(uavs(u), tasks, baseQ, t, cfg, lockTime, u);
bestOn = inf;
bestOnSlot = 1;
bestLast = inf;
bestLastSlot = 1;
hasLast = false;
for slotTry = 1:2
    trial = insertAt(baseQ, f, slotTry, k);
    if slotTry == 2 && isequal(trial, insertAt(baseQ, f, 1, k))
        continue
    end
    if isequal(trial, orig)
        continue
    end
    [othersOk, kOnTime, dFlight, tard] = scoreTrial( ...
        uavs(u), tasks, orig, baseQ, trial, k, t, cfg, readyFloor, u, uCur);
    if othersOk && kOnTime
        if ~mustPlace && ~latenessImproves(uavs, tasks, k, u, slotTry, t, cfg, lockTime, readyFloor)
            continue
        end
        c = dFlight + chi;
        if c < bestOn - 1e-9 || (abs(c - bestOn) <= 1e-9 && slotTry < bestOnSlot)
            bestOn = c;
            bestOnSlot = slotTry;
        end
    elseif mustPlace
        hasLast = true;
        if tard < bestLast - 1e-9 || (abs(tard - bestLast) <= 1e-9 && slotTry < bestLastSlot)
            bestLast = tard;
            bestLastSlot = slotTry;
        end
    end
end
if isfinite(bestOn)
    cost = bestOn;
    slot = bestOnSlot;
    return
end
if mustPlace && hasLast && isfinite(bestLast)
    cost = pol.lastResortBase + bestLast + chi;
    slot = bestLastSlot;
end
end

function [othersOk, kOnTime, dFlight, tardiness] = scoreTrial(uav, tasks, orig, baseQ, trial, k, t, cfg, readyFloor, uavIndex, uCur)
if uCur > 0 && uavIndex == uCur
    refQ = orig;
else
    refQ = baseQ;
end
[~, finRef] = walkQueue(uav, tasks, refQ, t, cfg, uavIndex, 0, -inf);
[~, finTrial, flightTrial] = walkQueue(uav, tasks, trial, t, cfg, uavIndex, k, readyFloor);
[~, ~, flightRef] = walkQueue(uav, tasks, refQ, t, cfg, uavIndex, 0, -inf);
dFlight = flightTrial - flightRef;
othersOk = true;
for p = 1:numel(refQ)
    j = refQ(p);
    if j == k
        continue
    end
    if finRef(p) > tasks(j).deadline + 1e-6
        continue
    end
    loc = find(trial == j, 1);
    if isempty(loc)
        continue
    end
    if finTrial(loc) > tasks(j).deadline + 1e-6
        othersOk = false;
        break
    end
end
kLoc = find(trial == k, 1);
kOnTime = ~isempty(kLoc) && finTrial(kLoc) <= tasks(k).deadline + 1e-6;
tardiness = 0;
for p = 1:numel(trial)
    j = trial(p);
    tardiness = tardiness + max(0, finTrial(p) - tasks(j).deadline);
end
end

function tf = latenessImproves(uavs, tasks, k, dest, slot, t, cfg, lockTime, readyFloor)
% Only the origin and destination queues change, so the fleet key
% moves exactly when those two queues do.
origin = tasks(k).assignedUAV;
[n1, d1] = pairLateness(uavs, tasks, origin, dest, t, cfg);
[u2, t2] = commitMove(uavs, tasks, k, dest, slot, t, cfg, lockTime, readyFloor);
[n2, d2] = pairLateness(u2, t2, origin, dest, t, cfg);
tf = (n2 < n1) || (n2 == n1 && d2 < d1 - 1e-3);
end

function [nLate, tardiness] = pairLateness(uavs, tasks, origin, dest, t, cfg)
idx = unique([origin, dest]);
idx = idx(idx >= 1 & idx <= numel(uavs));
nLate = 0;
tardiness = 0;
for n = 1:numel(idx)
    i = idx(n);
    q = asRow(uavs(i).queue);
    if isempty(q)
        continue
    end
    [~, fin] = walkQueue(uavs(i), tasks, q, t, cfg, i, 0, -inf);
    for p = 1:numel(q)
        late = fin(p) - tasks(q(p)).deadline;
        if late > 1e-6
            nLate = nLate + 1;
            tardiness = tardiness + late;
        end
    end
end
end

function [uavs, tasks] = commitMove(uavs, tasks, j, dest, slot, t, cfg, lockTime, readyFloor)
old = tasks(j).assignedUAV;
uavs = stripTask(uavs, j);
baseQ = asRow(uavs(dest).queue);
f = frozenPrefixLength(uavs(dest), tasks, baseQ, t, cfg, lockTime, dest);
uavs(dest).queue = insertAt(baseQ, f, slot, j);
uavs = refreshHeads(uavs);
tasks(j).assignedUAV = dest;
tasks(j).status = 'assigned';
tasks(j).atriskReason = '';
if old ~= dest
    tasks(j).arrivalTime = NaN;
    tasks(j).onStationUAV = 0;
end
if readyFloor > t
    tasks(j).commandReadyTime = readyFloor;
else
    tasks(j).commandReadyTime = 0;
end
end

function q = insertAt(baseQ, f, slot, k)
baseQ = asRow(baseQ);
baseQ = baseQ(baseQ ~= k);
if slot == 1
    f = min(max(0, f), numel(baseQ));
    q = [baseQ(1:f), k, baseQ(f+1:end)];
else
    q = [baseQ, k];
end
q = asRow(q);
end

%% ======================= PREDICTION =======================

function f = frozenPrefixLength(uav, tasks, q, t, cfg, lockTime, uavIndex)
q = asRow(q);
f = 0;
if isempty(q)
    return
end
[st, ~] = walkQueue(uav, tasks, q, t, cfg, uavIndex, 0, -inf);
for p = 1:numel(q)
    j = q(p);
    if isExecuting(uav, tasks, j, t, uavIndex) || st(p) <= lockTime + 1e-9
        f = p;
    else
        break
    end
end
end

function tf = anyFreeLate(uavs, tasks, t, cfg, lockTime)
tf = false;
for i = 1:numel(uavs)
    q = asRow(uavs(i).queue);
    if isempty(q)
        continue
    end
    f = frozenPrefixLength(uavs(i), tasks, q, t, cfg, lockTime, i);
    [~, fin] = walkQueue(uavs(i), tasks, q, t, cfg, i, 0, -inf);
    for p = (f + 1):numel(q)
        if fin(p) > tasks(q(p)).deadline + 1e-6
            tf = true;
            return
        end
    end
end
end

function [st, fi, flight] = walkQueue(uav, tasks, q, t, cfg, uavIndex, insertedId, readyFloor)
q = asRow(q);
nQ = numel(q);
st = zeros(1, nQ);
fi = zeros(1, nQ);
flight = 0;
if nQ == 0
    return
end
[delta, nomCap] = overload_params(cfg);
clock = t;
pos = uav.position;
speed = max(uav.speed, 1e-6);
for p = 1:nQ
    j = q(p);
    remainCount = nQ - p + 1;
    if isExecuting(uav, tasks, j, t, uavIndex)
        rem = remainingExec(tasks(j), remainCount, t, delta, nomCap);
        st(p) = tasks(j).arrivalTime;
        fi(p) = t + rem;
        clock = fi(p);
        pos = tasks(j).location;
        continue
    end
    travel = norm(tasks(j).location - pos) / speed;
    st(p) = clock + travel;
    if j == insertedId && readyFloor > st(p)
        st(p) = readyFloor;
    elseif j ~= insertedId && tasks(j).commandReadyTime > st(p)
        st(p) = tasks(j).commandReadyTime;
    end
    exec = stretched_exec(tasks(j).execTime, remainCount, delta, nomCap);
    fi(p) = st(p) + exec;
    flight = flight + travel;
    clock = fi(p);
    pos = tasks(j).location;
end
end

function rem = remainingExec(task, queueCount, t, delta, nomCap)
full = stretched_exec(task.execTime, queueCount, delta, nomCap);
spent = 0;
if ~isnan(task.arrivalTime)
    spent = max(0, t - task.arrivalTime);
end
rem = max(0, full - spent);
end

function tf = isExecuting(uav, tasks, j, t, uavIndex)
tf = false;
if j <= 0 || uav.assignedTask ~= j
    return
end
if norm(uav.position - tasks(j).location) > 1e-6
    return
end
if isnan(tasks(j).arrivalTime) || tasks(j).onStationUAV ~= uavIndex
    return
end
if (t - tasks(j).arrivalTime) <= 0
    return
end
tf = true;
end

function ok = hostCanDo(uavs, tasks, j)
ok = false;
i = tasks(j).assignedUAV;
if i > 0 && i <= numel(uavs)
    ok = isFeasible(tasks(j).requiredCap, uavs(i).capabilities);
end
end

function tf = isMovableStatus(task)
tf = strcmp(task.status, 'assigned') || strcmp(task.status, 'unassigned') || strcmp(task.status, 'atrisk');
end

%% ======================= ASSIGNMENT =======================

function colOfRow = solveLAP(C, unmatchedCost)
nRows = size(C, 1);
colOfRow = zeros(nRows, 1);
if nRows == 0 || isempty(C)
    return
end
if exist('matchpairs', 'file') ~= 2
    error('sim:noMatchpairs', ...
        'CARA needs matchpairs (Optimization Toolbox). Refusing the greedy fallback.');
end
Csafe = C;
Csafe(~isfinite(Csafe)) = 1e9;
M = matchpairs(Csafe, unmatchedCost);
for k = 1:size(M, 1)
    colOfRow(M(k, 1)) = M(k, 2);
end
end

function uavs = stripTask(uavs, j)
for i = 1:numel(uavs)
    if ~isempty(uavs(i).queue)
        uavs(i).queue = asRow(uavs(i).queue);
        uavs(i).queue = uavs(i).queue(uavs(i).queue ~= j);
    end
end
uavs = refreshHeads(uavs);
end

function uavs = refreshHeads(uavs)
for i = 1:numel(uavs)
    uavs(i).queue = asRow(uavs(i).queue);
    if isempty(uavs(i).queue)
        uavs(i).assignedTask = 0;
    else
        uavs(i).assignedTask = uavs(i).queue(1);
    end
end
end

function q = asRow(q)
if isempty(q)
    q = [];
else
    q = reshape(q, 1, []);
end
end

function p = percentile95(x)
x = sort(x(:));
if isempty(x)
    p = 0;
    return
end
idx = max(1, min(numel(x), ceil(0.95 * numel(x))));
p = x(idx);
end

%% ======================= STATE =======================

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
    'completeTime',NaN, 'arrivalTime',NaN, 'releaseTime',0, ...
    'onStationUAV',0, 'commandReadyTime',0), 1, n);
for j = 1:n
    tasks(j).name        = cfg.task(j).name;
    tasks(j).location    = cfg.task(j).location;
    tasks(j).requiredCap = cfg.task(j).requiredCap;
    tasks(j).execTime    = cfg.task(j).execTime;
    tasks(j).priority    = cfg.task(j).priority;
    tasks(j).deadline    = cfg.task(j).deadline;
    tasks(j).onStationUAV = 0;
    tasks(j).commandReadyTime = 0;
    if isfield(cfg.task(j), 'releaseTime') && ~isempty(cfg.task(j).releaseTime)
        tasks(j).releaseTime = cfg.task(j).releaseTime;
    else
        tasks(j).releaseTime = 0;
    end
end
end

function ok = isFeasible(requiredCap, uavCapabilities)
ok = all(ismember(requiredCap, uavCapabilities));
end

function [uavs, changed, degradedUAVs, degradedCaps] = fireCapabilityChanges(uavs, cfg, t)
changed = false;
degradedUAVs = [];
degradedCaps = {};
if isfield(cfg, 'capabilityChanges')
    cList = cfg.capabilityChanges;
elseif isfield(cfg, 'capabilityChange')
    cList = cfg.capabilityChange;
else
    return
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

function [uavs, tasks] = moveFleet(uavs, tasks, t, dt, cfg)
% Same flight and completion rule as every other method. A task that
% was just commanded waits until t + T_c before this aircraft starts it.
n = numel(uavs);
for i = 1:n
    j = uavs(i).assignedTask;
    if j == 0 && ~isempty(uavs(i).queue)
        j = uavs(i).queue(1);
    end
    flyDt = dt;
    tStamp = t;
    if j > 0 && tasks(j).commandReadyTime > t
        flyDt = max(0, (t + dt) - tasks(j).commandReadyTime);
        tStamp = t + (dt - flyDt);
    end
    if flyDt <= 1e-12
        continue
    end
    savedQ = cell(1, n);
    savedA = zeros(1, n);
    for k = 1:n
        if k == i
            continue
        end
        savedQ{k} = uavs(k).queue;
        savedA(k) = uavs(k).assignedTask;
        uavs(k).queue = [];
        uavs(k).assignedTask = 0;
    end
    [uavs, tasks] = move_fleet_step(uavs, tasks, tStamp, flyDt, cfg);
    for k = 1:n
        if k == i
            continue
        end
        uavs(k).queue = savedQ{k};
        uavs(k).assignedTask = savedA(k);
    end
end
end

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
if isempty(events)
    metrics.reallocationCount = 0;
else
    metrics.reallocationCount = sum(strcmp({events.trigger}, 'reactive'));
end
metrics.preemptionCount = 0;
completeTimes = [tasks(strcmp({tasks.status}, 'complete')).completeTime];
if isempty(completeTimes)
    metrics.meanCompletionTime = NaN;
else
    metrics.meanCompletionTime = mean(completeTimes);
end
pm = compute_paper_metrics(tasks, events, cfg, cfg.sim.tEnd);
metrics.R_task = pm.R_task;
metrics.R_time = pm.R_time;
metrics.CRI    = pm.CRI;
metrics.throughputRecovery = pm.throughputRecovery;
end
