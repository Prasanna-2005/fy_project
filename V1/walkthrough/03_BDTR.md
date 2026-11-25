# 03. BDTR: Bidirectional Task Reallocation

## 1. What it does

BDTR (Bidirectional Task Reallocation) responds when a UAV loses a payload. First it finds queued tasks that the damaged UAV can no longer do and moves each to a capable UAV with the shortest queue. Then it checks whether the damaged UAV still has useful payloads: if another UAV has at least two more queued tasks, BDTR may move a compatible task back to the damaged UAV. This is the “bidirectional” part: work can move away from a damaged UAV and later move back to it when its remaining payloads are still useful. [BDTR phases](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L164-L165) [Phase 2 load rule](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L222-L239)

## 2. Notation used

See [00_notation.md](00_notation.md) for the shared symbols and 1-based indexing rules. In this file, `u_fail` is the index of the UAV that just lost a payload; `u_d` is the most-loaded healthy donor UAV; `k_invalid` is the list of tasks on the failed UAV that now need a missing payload; and `k_star` is the task selected to move back to the failed UAV. The code's corresponding names are `u_fail`, `u_d`, `k_invalid`, and `k_star`. [BDTR reallocation inputs and invalid-task list](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L161-L172) [Donor and selected task](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L223-L254)

## 3. Code snippets

Each excerpt below is from [`2_BDTR/sim.m`](../../SRC_CODE/monte_carlo/2_BDTR/sim.m). It is shortened to the statements that control the relevant code path; the explanation tracks the omitted bookkeeping at the cited source lines too.

### A. Entry point and initial state

Source: [`sim.m` lines 1-32](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L1-L32)

```matlab
function result = sim(cfg, strategy)
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'common'));
if nargin < 1 || isempty(cfg)
    cfg = common_config('bdtr');
end
if nargin < 2 || isempty(strategy)
    strategy = 'bdtr';
end
if ~strcmp(strategy, 'bdtr')
    error('sim:unknownStrategy', 'Expected strategy "bdtr", got "%s".', strategy);
end
uavs  = makeFleet(cfg);
tasks = makeTaskSet(cfg);
events = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});
initTasks = find([tasks.releaseTime] <= 0);
pendingTasks = find([tasks.releaseTime] > 0);
for pIdx = pendingTasks
    tasks(pIdx).status = 'pending';
end
if ~isempty(initTasks)
    [uavs, tasks, ev0] = bdtrInitialAllocation(uavs, tasks, initTasks);
    events = [events, ev0];
end
```

**Line-by-line:**

- Line 1 defines `sim`, the function the experiment runner calls. It accepts a configuration and the selected strategy name, and returns a `result` structure.
- Line 2 adds the shared headless utilities folder to MATLAB's function search path.
- Lines 3-5 use the default BDTR configuration only when no configuration was supplied or it is empty.
- Lines 6-8 similarly default the strategy name to `bdtr`.
- Lines 9-11 reject any other strategy name, so this folder cannot accidentally run as another method.
- Lines 13-14 make the runtime UAV and task arrays from the configuration. The helper details are in section G below.
- Line 16 creates an empty event log. Each later event records its time, task index (or zero for a fleet-level failure), old and new UAV indices, trigger type, and reason.
- Line 19 collects task-array indices whose release time is at or before zero.
- Line 20 collects tasks whose release time is later than zero.
- Lines 21-23 mark those later tasks as `pending`, meaning they are not yet available for assignment.
- Lines 25-28 run the initial allocator only when at least one task is ready at time zero, then append its assignment events to the log.

### B. Mission-time loop, releases, and failures

Source: [`sim.m` lines 34-55](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L34-L55)

```matlab
for t = 0:cfg.sim.dt:cfg.sim.tEnd
    for j = 1:numel(tasks)
        if strcmp(tasks(j).status, 'pending') && t >= tasks(j).releaseTime
            [uavs, tasks, evRel] = bdtrAssignSingleTask(uavs, tasks, j, t);
            events = [events, evRel];
        end
    end
    [uavs, justChanged, degradedUAVs, degradedCaps] = fireCapabilityChanges(uavs, cfg, t);
    if justChanged
        for dIdx = 1:numel(degradedUAVs)
            u_fail = degradedUAVs(dIdx);
            events(end+1) = struct('time', t, 'taskIdx', 0, 'oldUAV', 0, ...
                'newUAV', u_fail, 'trigger', 'degradation', ...
                'reason', degradedCaps{dIdx});
            [uavs, tasks, evBDTR] = bdtrReallocation(uavs, tasks, u_fail, t, cfg);
            events = [events, evBDTR];
        end
    end
```

**Line-by-line:**

- Line 1 visits simulated times from 0 through the configured end time, advancing by `dt` seconds each time.
- Lines 2-3 scan every task and check whether it is pending and its release time has arrived.
- Line 4 gives each released task to the single-task allocator, which updates the UAV/task state and returns any event records.
- Line 5 adds those records to the shared event log.
- Line 7 applies every configured payload failure whose scheduled time is at or before the current time. The helper removes a payload only if that UAV still has it; see section H.
- Line 8 enters failure handling only when a payload was actually removed on this time step.
- Line 9 loops over each UAV affected on this time step, allowing multiple failures at the same time.
- Line 10 identifies the affected UAV as `u_fail`.
- Lines 11-13 record a fleet-level degradation event. `taskIdx = 0` means the event is about a UAV/payload, not one task; `reason` contains the payload name.
- Line 14 runs both BDTR reallocation phases for that failed UAV.
- Line 15 appends all task movements from those phases to the same event log.

The experiment runner supplies generated attack events to `cfg.capabilityChanges`, so the failure handler sees the same scheduled failures as the other methods in a paired trial. [Monte Carlo event setup](../../SRC_CODE/monte_carlo/run_monte_carlo.m#L78-L98)

### C. Deadline handling, movement, and return value

Source: [`sim.m` lines 57-86](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L57-L86)

```matlab
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
[uavs, tasks] = moveFleet(uavs, tasks, t, cfg.sim.dt, cfg);
result.uavs = uavs;
result.tasks = tasks;
result.events = events;
result.metrics = computeMissionMetrics(uavs, tasks, events, cfg);
result.strategy = strategy;
```

**Line-by-line:**

- The outer `for` scans each task once per time step.
- The first `if` skips tasks already complete, already failed, or not yet released.
- The next `if` checks whether the current time has reached the task's deadline.
- The assignment to `status` marks an unfinished overdue task as failed.
- `i` reads the task's current assigned UAV.
- The range check prevents indexing the UAV array with zero or an invalid number.
- The queue assignment removes task `j` from that UAV's queue.
- The next condition checks whether the failed task was also the UAV's active task at the front of its work.
- If other queued tasks remain, the first queued task becomes active; otherwise the active-task marker is set to zero.
- The nested `end` statements close the range check, active-task check, deadline check, task-state check, and task loop.
- `moveFleet` advances every UAV and updates any task that arrives or completes. It delegates to shared `move_fleet_step`; section I explains that code path.
- The result fields return final UAV state, final task state, the event log, computed metrics, and the strategy label.
- The last `end` closes the main `sim` function.

### D. Initial assignment

Source: [`sim.m` lines 90-131](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L90-L131)

```matlab
subPriorities = [tasks(taskIndices).priority];
[~, ord] = sortrows([-subPriorities(:), taskIndices(:)]);
orderedTasks = taskIndices(ord);
for idx = 1:numel(orderedTasks)
    k = orderedTasks(idx);
    req = tasks(k).requiredCap;
    cand = [];
    for u = 1:numel(uavs)
        if isFeasible(req, uavs(u).capabilities)
            cand(end+1) = u;
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
        ev0(end+1) = struct('time', 0, 'taskIdx', k, 'oldUAV', 0, ...
            'newUAV', u_target, 'trigger', 'initial', 'reason', 'BDTR-Initial');
    end
end
for i = 1:numel(uavs)
    if ~isempty(uavs(i).queue)
        uavs(i).assignedTask = uavs(i).queue(1);
    end
end
```

**Line-by-line:**

- The first line reads the priorities for only the selected task indices.
- `sortrows` sorts larger priorities before smaller ones by sorting the negative priority; task index is the tie-break, so equal priorities keep lower task indices first.
- The sorted order is translated back into task indices.
- The outer loop handles each task in that order.
- `k` is the task's array index.
- `req` is its required payload list.
- `cand` starts as an empty list of capable UAV indices.
- The inner loop checks each UAV.
- `isFeasible` returns true only when every required payload appears in that UAV's current capabilities; the following line adds that UAV index to `cand`.
- If no capable UAV exists, the task becomes at risk for reason `Capability`; it is not put in any queue.
- Otherwise, `arrayfun` gets the queue length of each candidate.
- `min` finds the smallest candidate queue length.
- `candMin` retains only candidates with that shortest queue.
- `min(candMin)` breaks a remaining tie by choosing the lowest UAV index.
- The next line appends task `k` to the chosen UAV's queue.
- The task records the chosen UAV index.
- Its status changes to assigned.
- An initial-assignment event is appended with time zero and reason `BDTR-Initial`.
- The `end` lines close the candidate branch and task loop.
- The final loop visits each UAV to set its active task to the first queued task when the queue is nonempty. Queue order therefore determines what it tries first.

### E. A task released after time zero

Source: [`sim.m` lines 133-159](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L133-L159)

```matlab
req = tasks(k).requiredCap;
cand = [];
for u = 1:numel(uavs)
    if isFeasible(req, uavs(u).capabilities)
        cand(end+1) = u;
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
    evRel(end+1) = struct('time', t, 'taskIdx', k, 'oldUAV', 0, ...
        'newUAV', u_target, 'trigger', 'reactive', 'reason', 'BDTR-MidwayRelease');
end
```

**Line-by-line:**

- `req` reads the payloads this newly released task needs.
- `cand` starts empty.
- The loop checks every UAV and adds indices for those passing `isFeasible`.
- If `cand` stays empty, the task becomes at risk due to capability mismatch.
- Otherwise, the next three lines calculate candidate queue lengths, find the minimum, and retain all candidates tied at that minimum.
- `min(candMin)` selects the lowest-index UAV among tied candidates.
- The task index is appended to the chosen queue.
- The task records its new assigned UAV and assigned status.
- If that UAV has no active task, the new task becomes active immediately; otherwise it waits in its queue.
- The final line records the move as a midway task release.
- The closing `end` statements finish the candidate branch and helper function.

The supplied scenario generator sets every task's release time to zero, so this helper is a supported code path but is not exercised by the default generated world. [Release-time assignment](../../SRC_CODE/monte_carlo/common/common_config.m#L63-L70) [Default release processing](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L23-L27)

### F. Reallocation after a payload failure

Source: [`sim.m` lines 161-220](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L161-L220)

```matlab
evBDTR = struct('time', {}, 'taskIdx', {}, 'oldUAV', {}, 'newUAV', {}, 'trigger', {}, 'reason', {});
q_fail = uavs(u_fail).queue;
k_invalid = [];
for idx = 1:numel(q_fail)
    k = q_fail(idx);
    if ~isFeasible(tasks(k).requiredCap, uavs(u_fail).capabilities)
        k_invalid(end+1) = k;
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
```

**Line-by-line:**

- The first line creates an empty list of reallocation events.
- `q_fail` copies the failed UAV's queue before any edits.
- `k_invalid` starts as an empty list of tasks that have become impossible for that UAV.
- The loop scans each queue entry.
- `k` reads the task-array index from that entry.
- `isFeasible` checks whether the task's full required payload list is still present on the failed UAV; only incompatible tasks enter `k_invalid`.
- The next line starts the phase only if at least one task is invalid.
- `priK` gathers those tasks' priorities.
- `sortrows` orders them by descending priority and then ascending task index.
- `k_invalid` is rearranged into that priority order.
- `setdiff(..., 'stable')` removes the invalid tasks from the failed UAV's queue while preserving the order of its remaining tasks.
- `ismember` checks whether the currently active task was among the removed tasks.
- If so, its `arrivalTime` is reset to `NaN`, so time spent by this UAV on the task does not count toward completion on another UAV.
- If the queue still has tasks, its first entry becomes active; otherwise the active marker becomes zero.

Source: [`sim.m` lines 189-220](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L189-L220)

```matlab
for idx = 1:numel(k_invalid)
    k = k_invalid(idx);
    tasks(k).arrivalTime = NaN;
    req = tasks(k).requiredCap;
    u_cand = [];
    for u = 1:numel(uavs)
        if isFeasible(req, uavs(u).capabilities)
            u_cand(end+1) = u;
        end
    end
    if ~isempty(u_cand)
        loads = arrayfun(@(u) numel(uavs(u).queue), uavs(u_cand));
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
        evBDTR(end+1) = struct('time', t, 'taskIdx', k, 'oldUAV', u_fail, ...
            'newUAV', u_target, 'trigger', 'reactive', 'reason', 'BDTR-Phase1-Offload');
    else
        tasks(k).assignedUAV = 0;
        tasks(k).status = 'atrisk';
        tasks(k).atriskReason = 'Capability';
    end
end
end
```

**Line-by-line:**

- The loop handles invalid tasks in priority order.
- `k` selects the next task index.
- `arrivalTime` is cleared because another UAV must start its own execution visit.
- `req` reads the task's requirement.
- `u_cand` starts empty.
- The loop tests every UAV against the task's required payloads after the failure has changed the fleet state.
- Capable UAV indices are appended to `u_cand`.
- If at least one candidate exists, the allocator measures those candidates' current queue lengths.
- It finds the minimum length and retains every candidate tied for that minimum.
- The lowest-index tied UAV becomes `u_target`.
- The task is appended to that UAV's queue.
- Its `assignedUAV` field is updated.
- Its status becomes assigned.
- Its at-risk reason is cleared.
- If the receiving UAV had no active task, this task becomes active.
- An event records the old failed UAV, new UAV, time, and Phase 1 reason.
- If there is no capable UAV, the task is made unassigned from any UAV (`assignedUAV = 0`), remains at risk, and records `Capability` as the reason.
- The two final `end` lines close the candidate branch and invalid-task loop; the next `end` closes the phase's nonempty check.

### G. Phase 2: use remaining payloads and reduce the queue gap

Source: [`sim.m` lines 222-280](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L222-L280)

```matlab
u_donor = setdiff(1:numel(uavs), u_fail);
while true
    if isempty(u_donor)
        break;
    end
    donor_loads = arrayfun(@(u) numel(uavs(u).queue), uavs(u_donor));
    maxLoad = max(donor_loads);
    candMax = u_donor(donor_loads == maxLoad);
    u_d = min(candMax);
    loadDiff = numel(uavs(u_d).queue) - numel(uavs(u_fail).queue);
    if loadDiff <= 1
        break;
    end
    candTasks = uavs(u_d).queue;
    swappable = [];
    for qIdx = candTasks
        if isFeasible(tasks(qIdx).requiredCap, uavs(u_fail).capabilities)
            if qIdx == uavs(u_d).assignedTask && ~isnan(tasks(qIdx).arrivalTime) && (t - tasks(qIdx).arrivalTime) > 0
                continue;
            end
            swappable(end+1) = qIdx;
        end
    end
    if ~isempty(swappable)
        k_star = swappable(1);
```

**Line-by-line:**

- `u_donor` is every UAV except the failed UAV; these are the possible donors.
- `while true` repeats balancing until a stop condition is reached.
- If there are no donors, `break` exits the loop.
- `donor_loads` measures each donor's queue length.
- `maxLoad` finds the greatest of those lengths.
- `candMax` keeps donor UAVs tied for the greatest load.
- `min(candMax)` breaks a tie by picking the lowest UAV index.
- `loadDiff` subtracts the failed UAV's queue length from the donor's queue length.
- A gap of 0 or 1 ends Phase 2; the transfer rule therefore runs only for a gap of at least 2.
- `candTasks` copies the chosen donor's current queue in its existing order.
- `swappable` starts as an empty task-index list.
- The loop considers donor tasks in queue order.
- `isFeasible` checks whether the failed UAV still has every payload required by this donor task.
- The nested condition detects the donor's active task if it has already arrived and started execution.
- `continue` skips that already-running task so the transfer does not interrupt it. A task at the front that has not arrived yet is not excluded by this guard.
- A compatible, non-skipped task is appended to `swappable`.
- If at least one task can move, `swappable(1)` chooses the first one in the donor queue. There is no priority comparison in this choice.

Source: [`sim.m` lines 256-280](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L256-L280)

```matlab
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
evBDTR(end+1) = struct('time', t, 'taskIdx', k_star, 'oldUAV', u_d, ...
    'newUAV', u_fail, 'trigger', 'reactive', 'reason', 'BDTR-Phase2-PullBack');
else
    u_donor = setdiff(u_donor, u_d);
end
end
```

**Line-by-line:**

- The first line removes `k_star` from the donor queue without changing the order of remaining tasks.
- The next condition checks whether the moved task was the donor's active task.
- If so, the donor's first remaining task becomes active, or zero if the queue is empty.
- The next line appends the selected task to the failed UAV's queue.
- If the failed UAV had no active task, the transferred task becomes its active task.
- The task records the receiving UAV.
- Its state is set to assigned.
- Its prior at-risk reason is cleared.
- `arrivalTime` is reset so the receiving UAV must do the task's execution time itself.
- The event log records the transfer as `BDTR-Phase2-PullBack`.
- If there were no swappable tasks, the current donor is removed from the donor list so the loop can examine the next-most-loaded donor instead of checking the same unusable queue again.
- The final two `end` lines close the swappable-task condition and the loop.

### H. Fleet/task construction, feasibility, and failure application

Sources: [`sim.m` lines 284-323](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L284-L323) and [`sim.m` lines 327-352](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L327-L352)

```matlab
n = numel(cfg.uav);
uavs = repmat(struct('name','', 'position',[0 0 0], 'capabilities',{{}}, ...
    'speed',0, 'assignedTask',0, 'queue',[]), 1, n);
for i = 1:n
    uavs(i).name = cfg.uav(i).name;
    uavs(i).position = cfg.uav(i).position;
    uavs(i).capabilities = cfg.uav(i).capabilities;
    uavs(i).speed = cfg.uav(i).speed;
    uavs(i).assignedTask = 0;
    uavs(i).queue = [];
end
```

**Line-by-line:** `n` counts configured UAVs. `repmat` creates an array of `n` runtime UAV records with empty/default fields. The loop copies each UAV's name, position, payload list, and speed from the configuration. It initializes the active-task index to zero and its queue to empty. These are state copies, so the simulation can change runtime capabilities and queues without rewriting the scenario configuration.

```matlab
n = numel(cfg.task);
tasks = repmat(struct('name','', 'location',[0 0 0], 'requiredCap',{{}}, ...
    'execTime',0, 'priority',1, 'deadline',Inf, 'assignedUAV',0, ...
    'status','unassigned', 'atriskReason','', ...
    'completeTime',NaN, 'arrivalTime',NaN, 'releaseTime',0), 1, n);
for j = 1:n
    tasks(j).name = cfg.task(j).name;
    tasks(j).location = cfg.task(j).location;
    tasks(j).requiredCap = cfg.task(j).requiredCap;
    tasks(j).execTime = cfg.task(j).execTime;
    tasks(j).priority = cfg.task(j).priority;
    tasks(j).deadline = cfg.task(j).deadline;
    if isfield(cfg.task(j), 'releaseTime') && ~isempty(cfg.task(j).releaseTime)
        tasks(j).releaseTime = cfg.task(j).releaseTime;
    else
        tasks(j).releaseTime = 0;
    end
end
```

**Line-by-line:** `n` counts configured tasks. `repmat` creates one runtime record per task, including status, assignment, completion, arrival, and release fields. The loop copies each configured task's name, location, required payloads, execution time, priority, and deadline. It copies `releaseTime` when present and nonempty; otherwise it uses zero. This helper does not assign tasks; the initial allocator does that afterward.

```matlab
function ok = isFeasible(requiredCap, uavCapabilities)
ok = all(ismember(requiredCap, uavCapabilities));
end
```

This helper tests payload compatibility. `ismember` checks each requirement against the UAV's available payload names; `all` makes the result true only if every required payload is available.

```matlab
for k = 1:numel(cList)
    cc = cList(k);
    if t >= cc.changeTime
        i = cc.uavIndex;
        if ismember(cc.capability, uavs(i).capabilities)
            uavs(i).capabilities = uavs(i).capabilities(~strcmp(uavs(i).capabilities, cc.capability));
            changed = true;
            degradedUAVs(end+1) = i;
            degradedCaps{end+1} = cc.capability;
        end
    end
end
```

`fireCapabilityChanges` first chooses `cfg.capabilityChanges`, or the singular legacy field if that is what the configuration contains; if neither exists, it returns without changing anything. The excerpt then scans each scheduled change. It waits until `t` reaches the change time, reads the affected UAV index, and checks that the UAV still has the named payload. If so, it filters that payload out, marks that a change occurred, and returns the affected UAV and payload in parallel lists. [Full handler](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L327-L352)

### I. Shared motion, completion, and metric calculation

Sources: [`sim.m` lines 356-396](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L356-L396), [`move_fleet_step.m`](../../SRC_CODE/monte_carlo/common/move_fleet_step.m#L1-L59), [`stretched_exec.m`](../../SRC_CODE/monte_carlo/common/stretched_exec.m#L1-L7), and [`compute_paper_metrics.m`](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L1-L108)

```matlab
function [uavs, tasks] = moveFleet(uavs, tasks, t, dt, cfg)
[uavs, tasks] = move_fleet_step(uavs, tasks, t, dt, cfg);
end
```

The wrapper passes all fleet/task state and the current time step to the shared movement routine. That routine loops over UAVs, chooses the first queued task when no active task is marked, moves toward its location by at most `speed * dt`, and checks payload feasibility after arrival. [Movement and active task](../../SRC_CODE/monte_carlo/common/move_fleet_step.m#L7-L29) When a UAV reaches a task, it records the arrival time for this UAV's visit. If its queue is above nominal capacity, `stretched_exec` increases execution duration from `execTime` to `execTime / delta`; otherwise the configured execution duration is used. [Arrival and execution](../../SRC_CODE/monte_carlo/common/move_fleet_step.m#L31-L45) [Overload rule](../../SRC_CODE/monte_carlo/common/stretched_exec.m#L1-L7) When elapsed on-station time reaches that duration, the task is marked complete, its completion time is recorded, and it is removed from the queue. [Completion update](../../SRC_CODE/monte_carlo/common/move_fleet_step.m#L43-L53)

`computeMissionMetrics` counts a task as feasible if it completed, or if it remains assigned to a UAV that still has the required payloads. It divides that count by the number of tasks for `feasibilityRate`; it separately divides the completed count by total tasks for `completionRate`, and similarly calculates `failedRate`. [Metric wrapper](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L363-L381) It averages the recorded completion times of completed tasks, returning `NaN` if none completed. [Mean time](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L383-L388)

The wrapper then calls `compute_paper_metrics`. In this code, at-risk tasks are identified by replaying the assignment event log at each payload-failure time. `nRealloc` counts at-risk tasks that eventually completed. `R_task` uses completed-task priorities plus the rescue bonus; `throughputRecovery` is `nRealloc / nAtRisk` (or 1 when no tasks were at risk). [At-risk replay and count](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L54-L69) [Task score and salvage fraction](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L81-L103)

`R_time` measures recovery after the failures: the helper replays queue assignments, looks for the point after the last failure when no UAV queue exceeds nominal capacity for a persistence window of at least five seconds, and scores the time from the first failure to that point relative to the remaining mission horizon. If the queues do not meet that condition by `tEnd`, the code treats recovery as not reached. [Recovery score](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L54-L78) [Equilibrium detection](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L163-L182) CRI is then the configured weighted average of `R_task` and `R_time`, with default `alpha = 0.5`. [CRI](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L105-L105) [Default weight](../../SRC_CODE/monte_carlo/common/common_config.m#L139-L142)

## 4. Line-by-line explanation until the end

The explanations immediately follow each code excerpt in Section 3, so each decision stays beside the lines that implement it. Together, subsections A-I trace the full `sim` path, including its helper functions and the shared movement and metric helpers.

## 5. Tiny scenario

This is the shared fixture defined in [01_common_setup.md](01_common_setup.md). The `T1` labels below map directly to `tasks(1)` through `tasks(4)`.

| UAV | Start position (m) | Payloads | Speed |
|---|---:|---|---:|
| U1 | [0, 0, 0] | Camera, Thermal | 1 m/s |
| U2 | [10, 0, 0] | Camera, Thermal | 1 m/s |

| Task | Location (m) | Needed payload | Execution | Deadline | Priority | Release |
|---|---:|---|---:|---:|---:|---:|
| T1 | [100, 0, 0] | Camera | 2 s | 200 s | 1 | 0 s |
| T2 | [100, 10, 0] | Camera | 2 s | 200 s | 1 | 0 s |
| T3 | [100, 20, 0] | Thermal | 2 s | 200 s | 1 | 0 s |
| T4 | [100, 30, 0] | Camera | 2 s | 200 s | 1 | 0 s |

Both UAVs begin with both payloads. At $t=12$ s, U1 loses Thermal. For this MATLAB check, the mission ends at 20 s, the time step is 1 s, and nominal queue capacity is set to two tasks. Those three values are test-fixture settings; they do not replace the benchmark defaults. [Benchmark defaults](../../SRC_CODE/monte_carlo/common/common_config.m#L139-L168)

## 6. Hand-traced log with reasoning

### Initial assignment at $t=0$ s

1. The initial allocator sorts tasks by descending priority, then task index. All four priorities are 1, so it visits T1, T2, T3, T4 in that order. [Sort rule](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L96-L102)
2. T1 needs Camera. U1 and U2 both have Camera and both queues are empty, so the tie goes to lower UAV index U1. Queues: U1 `[T1]`; U2 `[]`. [Candidate and tie rule](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L103-L121)
3. T2 needs Camera. Both UAVs can do it; U2 now has the shorter queue, so T2 goes to U2. Queues: U1 `[T1]`; U2 `[T2]`.
4. T3 needs Thermal. Both UAVs can do it and both queues have length one, so the tie goes to U1. Queues: U1 `[T1, T3]`; U2 `[T2]`.
5. T4 needs Camera. Both can do it, but U2 has one queued task while U1 has two, so T4 goes to U2. Final initial queues: U1 `[T1, T3]`; U2 `[T2, T4]`.

### Failure and two-way repair at $t=12$ s

1. The failure handler checks whether the scheduled time has arrived and whether U1 still has Thermal. Both checks pass; it removes Thermal from U1. The mission loop records a degradation event. [Failure condition and removal](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L340-L350) [Degradation log](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L44-L53)
2. Phase 1 scans U1's queue `[T1, T3]`. T1 needs Camera, which U1 still has, so it remains. T3 needs Thermal, which U1 no longer has, so T3 enters `k_invalid`. [Phase 1 feasibility scan](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L165-L172)
3. T3 is removed from U1's queue. U1's active task is T1, so its active task does not need replacement. The code clears T3's arrival time before giving it to another UAV. [Queue removal and clock reset](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L174-L192)
4. The Phase 1 candidate scan asks which UAV still has Thermal. U1 does not; U2 does. U2 is therefore the only candidate, even though its queue is longer. T3 is appended to U2's queue and its assignment becomes U2. [Candidate selection and commit](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L193-L218)
5. Phase 2 makes U2 the only donor. Its queue length is 3 (`[T2, T4, T3]`); U1's is 1 (`[T1]`); the gap is 2, so the transfer rule runs. [Donor and trigger](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L223-L239)
6. The donor queue is checked from front to back. T2 is Camera-compatible with U1. At the failure time it has not arrived at its distant task location, so the “do not interrupt a task already in execution” guard does not skip it. T2 enters the swappable list. T4 is also Camera-compatible and is still queued, so it is added after T2. T3 requires Thermal and is not compatible with U1, so it is not added. [Swappable scan](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L241-L250)
7. The first swappable task is T2 because queue order, not priority or distance, decides. BDTR removes T2 from U2 and appends it to U1. The final queues are U1 `[T1, T2]`; U2 `[T4, T3]`. [Queue-order choice and transfer](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L252-L275)
8. The gap is now `2 - 2 = 0`, so the next Phase 2 loop pass stops. [Repeat and stop condition](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L225-L239)
9. At each remaining time step through 20 s, the UAVs move toward their active tasks. The task sites are about 80 m or more away, so neither UAV reaches one by the end of this tiny run; all four tasks remain assigned and none completes. [Movement distance calculation](../../SRC_CODE/monte_carlo/common/move_fleet_step.m#L18-L25) [Completion requires arrival](../../SRC_CODE/monte_carlo/common/move_fleet_step.m#L31-L46)

The key contrast is visible at the failure: Phase 1 moves the task that U1 can no longer do (T3) away from U1; Phase 2 uses U1's still-working Camera payload to take a task (T2) back from U2, whose queue had become longer.

## 7. Verification

I ran the fixture with MATLAB R2026a through the actual `2_BDTR/sim.m` function, using the exact UAVs, tasks, failure time, `dt`, end time, and capacity stated above. MATLAB returned these event rows:

| Time (s) | Trigger | Task index | Old UAV | New UAV | Reason |
|---:|---|---:|---:|---:|---|
| 0 | initial | 1 | 0 | 1 | BDTR-Initial |
| 0 | initial | 2 | 0 | 2 | BDTR-Initial |
| 0 | initial | 3 | 0 | 1 | BDTR-Initial |
| 0 | initial | 4 | 0 | 2 | BDTR-Initial |
| 12 | degradation | 0 | 0 | 1 | Thermal |
| 12 | reactive | 3 | 1 | 2 | BDTR-Phase1-Offload |
| 12 | reactive | 2 | 2 | 1 | BDTR-Phase2-PullBack |

The final MATLAB queues were U1 `[1, 2]` and U2 `[4, 3]`; all four tasks had status `assigned`. The event table and queue result were produced by executing the simulator. The numbered reasoning above was traced against the source and cross-checked against that run. I did not run the full Monte Carlo or attack-sweep experiment for this walkthrough.

### Unclear behavior

No BDTR decision in this trace was unclear. One behavior worth noting is explicit in the code: Phase 2 protects an active task only after it has arrived and begun execution; the guard does not protect an active task that is still traveling. The code comment describes this as not interrupting a task actively in execution. [Guard and comment](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L243-L248)
