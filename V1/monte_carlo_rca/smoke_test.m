%% SMOKE_TEST  BDTR Sanity-Check, Protocol Invariants & Algorithm 1 Unit Verification
%
% Combines:
%   Part 1: Deterministic sanity checks across Small (5 UAVs, 80 tasks) & Large (10 UAVs, 120 tasks)
%           under both 'exact_paper' (paper_aligned) and 'before' (realistic_local) profiles.
%           Verifies travel mode, failedRate == 0 invariant, and strict determinism.
%   Part 2: Hand-built step-by-step verification of BDTR Algorithm 1:
%           - Case 1: Phase 1 offload & Phase 2 gap <= 1 stopping condition (3 UAVs, 5 tasks)
%           - Case 2: Phase 2 pull-back & in-progress head-task filter deviation (3 UAVs, 7 tasks)

clear; clc; close all;

baseDir = fileparts(mfilename('fullpath'));
addpath(baseDir);
addpath(fullfile(baseDir, 'common'));
addpath(fullfile(baseDir, 'BDTR'));

warnState = warning('off', 'MATLAB:dispatcher:nameConflict');
cleanupWarn = onCleanup(@() warning(warnState));

%% ======================= PART 1: PROFILE INVARIANTS & DETERMINISM =======================

scenarios = {
    'small', 'Scenario 1 (Small: 5 UAVs, 2 Payloads, 80 Tasks)';
    'large', 'Scenario 2 (Large: 10 UAVs, 3 Payloads, 120 Tasks)'
};

profiles = {
    'paper_aligned',   'Exact Paper (Zeng 2026 §V.A: No travel, d = Inf)';
    'realistic_local', 'Before / Local (5 m/s travel, finite deadlines)'
};

fixedSeed = 42;

fprintf('\n====================================================================================================\n');
fprintf('                      PART 1: BDTR SANITY CHECK & PROTOCOL INVARIANT VERIFICATION\n');
fprintf('====================================================================================================\n');

for pi = 1:size(profiles, 1)
    profTag   = profiles{pi, 1};
    profLabel = profiles{pi, 2};

    fprintf('\n════ PROFILE: %s ════\n', upper(profLabel));
    fprintf('%-10s %-8s %8s %8s %8s %10s %10s %12s %12s\n', ...
        'Algorithm', 'Scenario', 'R_task', 'R_time', 'CRI', 'CompRate', 'FailRate', 'TravelMode', 'DetermTest');
    fprintf('%s\n', repmat('-', 1, 100));

    for sc = 1:size(scenarios, 1)
        scName = scenarios{sc, 1};

        cd(fullfile(baseDir, 'BDTR'));
        clear sim;

        % --- Run 1 ---
        cfg1 = apply_v2_profile(common_config('bdtr', scName, fixedSeed), profTag);
        cfg1.sim.visualize = false;
        cfg1.capabilityChanges = generate_attack_events(cfg1, 0.30, 'random', fixedSeed);

        if strcmp(profTag, 'paper_aligned')
            assert(~cfg1.sim.includeTravel, 'Invariant violation: includeTravel is not false in paper_aligned');
        else
            assert(cfg1.sim.includeTravel, 'Invariant violation: includeTravel is not true in realistic_local');
        end

        res1 = sim(cfg1, 'bdtr');
        m1 = res1.metrics;

        if strcmp(profTag, 'paper_aligned')
            assert(m1.failedRate == 0, 'Invariant violation: failedRate is %f (expected 0.0 for paper_aligned)', m1.failedRate);
        end

        % --- Run 2: Exact same seed to verify determinism ---
        clear sim;
        cfg2 = apply_v2_profile(common_config('bdtr', scName, fixedSeed), profTag);
        cfg2.sim.visualize = false;
        cfg2.capabilityChanges = generate_attack_events(cfg2, 0.30, 'random', fixedSeed);

        res2 = sim(cfg2, 'bdtr');
        m2 = res2.metrics;

        isDeterministic = (abs(m1.completionRate - m2.completionRate) < 1e-12) && ...
                          (abs(m1.CRI - m2.CRI) < 1e-12) && ...
                          (abs(m1.R_task - m2.R_task) < 1e-12) && ...
                          (abs(m1.R_time - m2.R_time) < 1e-12);
        assert(isDeterministic, 'Invariant violation: Non-deterministic execution detected between Run 1 and Run 2');

        if cfg1.sim.includeTravel
            travelStr = '5 m/s flight';
        else
            travelStr = '0 s (excl)';
        end

        fprintf('%-10s %-8s %8.3f %8.3f %8.3f %9.1f%% %9.1f%% %12s %12s\n', ...
            'BDTR', scName, m1.R_task, m1.R_time, m1.CRI, ...
            m1.completionRate*100, m1.failedRate*100, travelStr, 'PASS (exact)');
    end
end

%% ======================= PART 2: BDTR ALGORITHM 1 UNIT VERIFICATION =======================

fprintf('\n====================================================================================================\n');
fprintf('                      PART 2: BDTR ALGORITHM 1 STEP-BY-STEP UNIT VERIFICATION\n');
fprintf('====================================================================================================\n\n');

% Case 1: Pure 3-UAV, 5-Task Case (Gap <= 1 stopping condition)
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

cd(fullfile(baseDir, 'BDTR')); clear sim;
u1 = sim(cfg1, 'bdtr');
assert(isequal(u1.uavs(1).queue, 2),      'Case 1 Failed: UAV1 queue mismatch');
assert(isequal(u1.uavs(2).queue, [3 4]),  'Case 1 Failed: UAV2 queue mismatch');
assert(isequal(u1.uavs(3).queue, [5 1]),  'Case 1 Failed: UAV3 queue mismatch');
fprintf('[PASS] Unit Case 1: Phase 1 offload [UAV1->UAV3] & Phase 2 gap <= 1 termination verified.\n');

% Case 2: 3-UAV, 7-Task Case (Phase 2 Pull-Back & In-Progress Filter Deviation)
cfg2 = cfg1;
cfg2.task(1) = struct('name','T1', 'location',[0 0 0], 'requiredCap',{{'Thermal'}}, 'execTime',50, 'priority',3, 'deadline',Inf, 'releaseTime',0);
cfg2.task(2) = struct('name','T2', 'location',[0 0 0], 'requiredCap',{{'Thermal'}}, 'execTime',50, 'priority',3, 'deadline',Inf, 'releaseTime',0);
cfg2.task(3) = struct('name','T3', 'location',[0 0 0], 'requiredCap',{{'Camera'}},  'execTime',50, 'priority',2, 'deadline',Inf, 'releaseTime',0);
cfg2.task(4) = struct('name','T4', 'location',[0 0 0], 'requiredCap',{{'Thermal'}}, 'execTime',50, 'priority',2, 'deadline',Inf, 'releaseTime',0);
cfg2.task(5) = struct('name','T5', 'location',[0 0 0], 'requiredCap',{{'Camera'}},  'execTime',50, 'priority',2, 'deadline',Inf, 'releaseTime',0);
cfg2.task(6) = struct('name','T6', 'location',[0 0 0], 'requiredCap',{{'Camera'}},  'execTime',50, 'priority',2, 'deadline',Inf, 'releaseTime',0);
cfg2.task(7) = struct('name','T7', 'location',[0 0 0], 'requiredCap',{{'Camera'}},  'execTime',50, 'priority',1, 'deadline',Inf, 'releaseTime',0);

u2 = sim(cfg2, 'bdtr');
assert(isequal(u2.uavs(1).queue, [6 5]),    'Case 2 Failed: UAV1 queue mismatch');
assert(isequal(u2.uavs(2).queue, [3 7]),    'Case 2 Failed: UAV2 queue mismatch');
assert(isequal(u2.uavs(3).queue, [2 1 4]),  'Case 2 Failed: UAV3 queue mismatch');
pullBackEvents = u2.events(strcmp({u2.events.reason}, 'BDTR-Phase2-PullBack'));
assert(~isempty(pullBackEvents) && pullBackEvents(1).taskIdx == 5, ...
    'Case 2 Failed: Expected Task 5 to be pulled back due to in-progress filter on Task 3');
fprintf('[PASS] Unit Case 2: Phase 2 pull-back triggered (Task 3 executing skipped; Task 5 transferred).\n');

fprintf('\n%s\n', repmat('=', 1, 100));
fprintf('[PASS] All BDTR smoke tests, protocol invariants, and Algorithm 1 unit checks PASSED.\n\n');
cd(baseDir);
