%% SMOKE_TEST  Rapid Developer Sanity-Check & Protocol Invariant Verification
%
% Executes deterministic sanity checks across:
%   - All 6 solvers: 1_RRAM, 2_BDTR, 3_SROM, 4_HUNGARIAN, 5_SABR, 6_CARA
%   - Both Scenarios: Scenario 1 (Small: 5 UAVs, 80 tasks), Scenario 2 (Large: 10 UAVs, 120 tasks)
%   - Under paper_aligned profile:
%     1. Confirms no travel delay (includeTravel = false)
%     2. Confirms failedRate = 0 by design (infinite deadlines)
%     3. Confirms determinism (exact same seed produces identical results twice)

clear; clc; close all;

baseDir = fileparts(mfilename('fullpath'));
addpath(baseDir);
addpath(fullfile(baseDir, 'common'));

warnState = warning('off', 'MATLAB:dispatcher:nameConflict');
cleanupWarn = onCleanup(@() warning(warnState));

cases = {
    '1_RRAM',          'rram',     'RRAM (Baseline)';
    '2_BDTR',          'bdtr',     'BDTR (Baseline)';
    '3_SROM',          'srom',     'SROM (Baseline)';
    '4_HUNGARIAN',     'reactive', 'Hungarian (Ours)';
    '5_SABR',          'sabr',     'SABR';
    '6_CARA',          'cara',     'CARA'
};

scenarios = {
    'small', 'Scenario 1 (Small: 5 UAVs, 2 Payloads, 80 Tasks)';
    'large', 'Scenario 2 (Large: 10 UAVs, 3 Payloads, 120 Tasks)'
};

results = struct();

fprintf('\n=========================================================================================================================\n');
fprintf('                           MULTI-UAV BASELINE METHODS SANITY CHECK & DETERMINISM TEST\n');
fprintf('                                Profile: paper_aligned (No travel, failedRate = 0)\n');
fprintf('=========================================================================================================================\n');

fixedSeed = 42;

for sc = 1:size(scenarios, 1)
    scName  = scenarios{sc, 1};
    scLabel = scenarios{sc, 2};

    fprintf('\n── %s ──\n', upper(scLabel));
    fprintf('%-16s %-20s %8s %8s %8s %8s %8s %10s %10s\n', ...
        'Directory', 'Algorithm', 'R_task', 'R_time', 'CRI', 'CompRate', 'FailRate', 'NoTravel', 'DetermTest');
    fprintf('%s\n', repmat('-', 1, 110));

    for c = 1:size(cases, 1)
        dirName = cases{c, 1};
        strat   = cases{c, 2};
        label   = cases{c, 3};

        cd(fullfile(baseDir, dirName));
        clear sim;

        % --- Run 1 ---
        cfg1 = apply_v2_profile(common_config(strat, scName, fixedSeed), 'paper_aligned');
        cfg1.sim.visualize = false;
        cfg1.capabilityChanges = generate_attack_events(cfg1, 0.30, 'random', fixedSeed);

        % Invariant 1: includeTravel must be false in paper_aligned
        assert(~cfg1.sim.includeTravel, 'Invariant violation: includeTravel is not false in paper_aligned');

        res1 = sim(cfg1, strat);
        m1 = res1.metrics;

        % Invariant 2: failedRate must be exactly 0 for reproduction methods (infinite deadlines)
        if ~strcmp(strat, 'cara')
            assert(m1.failedRate == 0, 'Invariant violation: failedRate is %f (expected 0.0 for %s)', m1.failedRate, label);
        end

        % --- Run 2: Exact same seed to verify determinism ---
        clear sim;
        cfg2 = apply_v2_profile(common_config(strat, scName, fixedSeed), 'paper_aligned');
        cfg2.sim.visualize = false;
        cfg2.capabilityChanges = generate_attack_events(cfg2, 0.30, 'random', fixedSeed);

        res2 = sim(cfg2, strat);
        m2 = res2.metrics;

        % Invariant 3: Determinism check (Run 1 == Run 2)
        diffComp = abs(m1.completionRate - m2.completionRate);
        diffCRI  = abs(m1.CRI - m2.CRI);
        diffRtask = abs(m1.R_task - m2.R_task);
        diffRtime = abs(m1.R_time - m2.R_time);
        isDeterministic = (diffComp < 1e-12) && (diffCRI < 1e-12) && (diffRtask < 1e-12) && (diffRtime < 1e-12);
        assert(isDeterministic, 'Invariant violation: Non-deterministic execution detected between Run 1 and Run 2');

        fieldTag = sprintf('%s_%s', matlab.lang.makeValidName(dirName), scName);
        results.(fieldTag) = res1;

        travelStr = 'PASS (false)';
        determStr = 'PASS (exact)';

        fprintf('%-16s %-20s %8.3f %8.3f %8.3f %7.1f%% %7.1f%% %10s %10s\n', ...
            dirName, label, m1.R_task, m1.R_time, m1.CRI, ...
            m1.completionRate*100, m1.failedRate*100, travelStr, determStr);
    end
end

fprintf('\n%s\n', repmat('=', 1, 110));
fprintf('[PASS] All smoke tests and protocol invariants passed successfully across all 6 algorithms.\n\n');
cd(baseDir);
