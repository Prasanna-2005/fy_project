%% TEST_BDTR_VERIFICATION
% Hand-built deterministic verification of BDTR Algorithm 1.
% Verifies:
%  1. Phase 1: Invalid tasks sorted by priority (descending, tie-break lowest index),
%     reallocated to min-load candidate UAV (tie-break lowest index).
%  2. Phase 2: Donor chosen by max-load (tie-break lowest index), swap triggered
%     when gap >= 2, terminated when gap <= 1.
%  3. Records the in-progress head-task filter as an explicit deviation.

clear; clc;
baseDir = fileparts(mfilename('fullpath'));
addpath(fullfile(baseDir, 'common'));
addpath(fullfile(baseDir, '2_BDTR'));

fprintf('====================================================================\n');
fprintf('     BDTR ALGORITHM 1 STEP-BY-STEP HAND-BUILT VERIFICATION TEST     \n');
fprintf('====================================================================\n\n');

%% Case 1: Pure 3-UAV, 5-Task Case (Gap <= 1 stopping condition)
% 3 UAVs:
%   UAV1: [Camera, Thermal]
%   UAV2: [Camera]
%   UAV3: [Thermal]
% 5 Tasks:
%   T1: Thermal, pri 3 -> initial goes to UAV1 (tie-break over UAV3)
%   T2: Camera,  pri 1 -> initial goes to UAV1
%   T3: Camera,  pri 2 -> initial goes to UAV2
%   T4: Camera,  pri 1 -> initial goes to UAV2
%   T5: Thermal, pri 2 -> initial goes to UAV3
%
% Initial queues at t=0:
%   UAV1: [1, 2] (len 2)
%   UAV2: [3, 4] (len 2)
%   UAV3: [5]    (len 1)
%
% At t=5, UAV1 loses Thermal.
% Expected Phase 1:
%   T1 requires Thermal -> invalid on UAV1.
%   Offloaded to UAV3 (only capable UAV, len 1).
%   UAV1 queue becomes [2] (len 1).
%   UAV3 queue becomes [5, 1] (len 2).
%   UAV2 queue is [3, 4] (len 2).
% Expected Phase 2:
%   Donors: UAV2 (len 2), UAV3 (len 2). Max load = 2.
%   Candidate max: UAV2 (lowest index).
%   Gap: |Q_2| - |Q_1| = 2 - 1 = 1 <= 1.
%   Phase 2 triggers NO transfer and immediately terminates!
%   Final queues: UAV1: [2], UAV2: [3, 4], UAV3: [5, 1].

cfg1 = struct();
cfg1.sim.dt = 1; cfg1.sim.tEnd = 20; cfg1.sim.visualize = false; cfg1.sim.includeTravel = false;
cfg1.bdtr.gamma = 0.5; cfg1.bdtr.delta = 0.9; cfg1.bdtr.alpha = 0.5; cfg1.bdtr.nominalCapacity = 3;

cfg1.uav(1) = struct('name','UAV1', 'position',[0 0 0], 'capabilities',{{'Camera','Thermal'}}, 'speed',5);
cfg1.uav(2) = struct('name','UAV2', 'position',[0 0 0], 'capabilities',{{'Camera'}}, 'speed',5);
cfg1.uav(3) = struct('name','UAV3', 'position',[0 0 0], 'capabilities',{{'Thermal'}}, 'speed',5);

cfg1.task(1) = struct('name','T1', 'location',[0 0 0], 'requiredCap',{{'Thermal'}}, 'execTime',50, 'priority',3, 'deadline',Inf, 'releaseTime',0);
cfg1.task(2) = struct('name','T2', 'location',[0 0 0], 'requiredCap',{{'Camera'}},  'execTime',50, 'priority',1, 'deadline',Inf, 'releaseTime',0);
cfg1.task(3) = struct('name','T3', 'location',[0 0 0], 'requiredCap',{{'Camera'}},  'execTime',50, 'priority',2, 'deadline',Inf, 'releaseTime',0);
cfg1.task(4) = struct('name','T4', 'location',[0 0 0], 'requiredCap',{{'Camera'}},  'execTime',50, 'priority',1, 'deadline',Inf, 'releaseTime',0);
cfg1.task(5) = struct('name','T5', 'location',[0 0 0], 'requiredCap',{{'Thermal'}}, 'execTime',50, 'priority',2, 'deadline',Inf, 'releaseTime',0);

cfg1.capabilityChanges(1) = struct('uavIndex', 1, 'capability', 'Thermal', 'changeTime', 5);

cd(fullfile(baseDir, '2_BDTR')); clear sim;
res1 = sim(cfg1, 'bdtr');

fprintf('--- Case 1: Initial Allocation & Phase 1 Offload ---\n');
fprintf('UAV1 queue: [%s] (expected [2])\n', num2str(res1.uavs(1).queue));
fprintf('UAV2 queue: [%s] (expected [3  4])\n', num2str(res1.uavs(2).queue));
fprintf('UAV3 queue: [%s] (expected [5  1])\n', num2str(res1.uavs(3).queue));

assert(isequal(res1.uavs(1).queue, 2), 'Case 1 Failed: UAV1 queue mismatch');
assert(isequal(res1.uavs(2).queue, [3 4]), 'Case 1 Failed: UAV2 queue mismatch');
assert(isequal(res1.uavs(3).queue, [5 1]), 'Case 1 Failed: UAV3 queue mismatch');
fprintf('[PASS] Case 1 passed: Phase 1 offload and gap <= 1 termination verified.\n\n');

%% Case 2: 3-UAV, 7-Task Case (Phase 2 Pull-Back & In-Progress Filter Deviation)
% 3 UAVs:
%   UAV1: [Camera, Thermal]
%   UAV2: [Camera]
%   UAV3: [Thermal]
% 7 Tasks:
%   T1: Thermal, pri 3 -> UAV1 [1]
%   T2: Thermal, pri 3 -> UAV3 [2]
%   T3: Camera,  pri 2 -> UAV2 [3]
%   T4: Thermal, pri 2 -> UAV1 [1, 4] (tie-break over UAV3)
%   T5: Camera,  pri 2 -> UAV2 [3, 5]
%   T6: Camera,  pri 2 -> UAV1 [1, 4, 6] (tie-break over UAV2)
%   T7: Camera,  pri 1 -> UAV2 [3, 5, 7]
%
% Initial queues at t=0:
%   UAV1: [1, 4, 6] (len 3: 2 Thermal, 1 Camera)
%   UAV2: [3, 5, 7] (len 3: 3 Camera)
%   UAV3: [2]       (len 1: 1 Thermal)
%
% At t=5, UAV1 loses Thermal.
% Phase 1:
%   T1 and T4 both invalid on UAV1.
%   Sorted by priority: T1 (pri 3), then T4 (pri 2).
%   Both offloaded to UAV3 (loads: 1 -> 2 -> 3).
%   UAV1 queue becomes [6] (len 1).
%   UAV3 queue becomes [2, 1, 4] (len 3).
% Phase 2:
%   Donors: UAV2 (len 3), UAV3 (len 3). Max load = 3.
%   Tie-break lowest index: u_d = 2 (UAV2).
%   Gap: |Q_2| - |Q_1| = 3 - 1 = 2 >= 2 -> Trigger pull-back!
%   Tasks in Q_2: [3, 5, 7].
%   [DEVIATION NOTE]: T3 is actively executing on UAV2 at t=5 (arrived at t=0, elapsed = 5s).
%   The in-progress filter skips T3!
%   Earliest swappable available task is T5!
%   T5 is pulled back to UAV1!
%   UAV2 queue becomes [3, 7] (len 2).
%   UAV1 queue becomes [6, 5] (len 2).
% Next iteration:
%   Max donor: UAV3 (len 3).
%   Gap: |Q_3| - |Q_1| = 3 - 2 = 1 <= 1 -> Stop!
% Final queues:
%   UAV1: [6, 5]
%   UAV2: [3, 7]
%   UAV3: [2, 1, 4]

cfg2 = cfg1;
cfg2.task(1) = struct('name','T1', 'location',[0 0 0], 'requiredCap',{{'Thermal'}}, 'execTime',50, 'priority',3, 'deadline',Inf, 'releaseTime',0);
cfg2.task(2) = struct('name','T2', 'location',[0 0 0], 'requiredCap',{{'Thermal'}}, 'execTime',50, 'priority',3, 'deadline',Inf, 'releaseTime',0);
cfg2.task(3) = struct('name','T3', 'location',[0 0 0], 'requiredCap',{{'Camera'}},  'execTime',50, 'priority',2, 'deadline',Inf, 'releaseTime',0);
cfg2.task(4) = struct('name','T4', 'location',[0 0 0], 'requiredCap',{{'Thermal'}}, 'execTime',50, 'priority',2, 'deadline',Inf, 'releaseTime',0);
cfg2.task(5) = struct('name','T5', 'location',[0 0 0], 'requiredCap',{{'Camera'}},  'execTime',50, 'priority',2, 'deadline',Inf, 'releaseTime',0);
cfg2.task(6) = struct('name','T6', 'location',[0 0 0], 'requiredCap',{{'Camera'}},  'execTime',50, 'priority',2, 'deadline',Inf, 'releaseTime',0);
cfg2.task(7) = struct('name','T7', 'location',[0 0 0], 'requiredCap',{{'Camera'}},  'execTime',50, 'priority',1, 'deadline',Inf, 'releaseTime',0);

res2 = sim(cfg2, 'bdtr');

fprintf('--- Case 2: Phase 2 Pull-Back & In-Progress Filter Deviation ---\n');
fprintf('UAV1 queue: [%s] (expected [6  5])\n', num2str(res2.uavs(1).queue));
fprintf('UAV2 queue: [%s] (expected [3  7])\n', num2str(res2.uavs(2).queue));
fprintf('UAV3 queue: [%s] (expected [2  1  4])\n', num2str(res2.uavs(3).queue));

assert(isequal(res2.uavs(1).queue, [6 5]), 'Case 2 Failed: UAV1 queue mismatch');
assert(isequal(res2.uavs(2).queue, [3 7]), 'Case 2 Failed: UAV2 queue mismatch');
assert(isequal(res2.uavs(3).queue, [2 1 4]), 'Case 2 Failed: UAV3 queue mismatch');

% Check recorded events
pullBackEvents = res2.events(strcmp({res2.events.reason}, 'BDTR-Phase2-PullBack'));
assert(~isempty(pullBackEvents), 'Case 2 Failed: No Phase 2 pull-back event generated');
assert(pullBackEvents(1).taskIdx == 5, 'Case 2 Failed: Expected Task 5 to be pulled back due to in-progress filter on Task 3');

fprintf('[PASS] Case 2 passed: Phase 2 pull-back triggered when gap >= 2.\n');
fprintf('[DEVIATION CONFIRMED]: Task 3 was skipped because it was in execution; Task 5 was transferred.\n\n');
fprintf('All BDTR algorithm verification checks PASSED.\n');
cd(baseDir);
