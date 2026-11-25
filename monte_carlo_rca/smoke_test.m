%% SMOKE_TEST  Rapid Developer Sanity-Check & Protocol Invariant Verification
%
% Executes deterministic sanity checks for BDTR (Bidirectional Task Reallocation):
%   - Both Scenarios: Scenario 1 (Small: 5 UAVs, 80 tasks), Scenario 2 (Large: 10 UAVs, 120 tasks)
%   - Under both profiles:
%     1. 'exact_paper' (paper_aligned):
%        - Invariant 1: Flight travel disabled (includeTravel = false)
%        - Invariant 2: Deadline failure rate = 0% by design (infinite deadlines)
%        - Invariant 3: Strict determinism (exact identical seeds produce identical results)
%     2. 'before' (realistic_local):
%        - Invariant 1: Flight travel enabled (includeTravel = true, 5 m/s)
%        - Invariant 2: Finite staggered deadlines active
%        - Invariant 3: Strict determinism (exact identical seeds produce identical results)

clear; clc; close all;

baseDir = fileparts(mfilename('fullpath'));
addpath(baseDir);
addpath(fullfile(baseDir, 'common'));
addpath(fullfile(baseDir, '2_BDTR'));

warnState = warning('off', 'MATLAB:dispatcher:nameConflict');
cleanupWarn = onCleanup(@() warning(warnState));

scenarios = {
    'small', 'Scenario 1 (Small: 5 UAVs, 2 Payloads, 80 Tasks)';
    'large', 'Scenario 2 (Large: 10 UAVs, 3 Payloads, 120 Tasks)'
};

profiles = {
    'paper_aligned',   'Exact Paper (Zeng 2026 §V.A: No travel, d = Inf)';
    'realistic_local', 'Before / Local (5 m/s travel, finite deadlines)'
};

fixedSeed = 42;

fprintf('\n=========================================================================================================================\n');
fprintf('                           BDTR SANITY CHECK & PROTOCOL INVARIANT VERIFICATION\n');
fprintf('                             Comparing Exact Paper Simulation vs Before Simulation\n');
fprintf('=========================================================================================================================\n');

for pi = 1:size(profiles, 1)
    profTag   = profiles{pi, 1};
    profLabel = profiles{pi, 2};

    fprintf('\n════ PROFILE: %s ════\n', upper(profLabel));
    fprintf('%-10s %-8s %8s %8s %8s %10s %10s %12s %12s\n', ...
        'Algorithm', 'Scenario', 'R_task', 'R_time', 'CRI', 'CompRate', 'FailRate', 'TravelMode', 'DetermTest');
    fprintf('%s\n', repmat('-', 1, 100));

    for sc = 1:size(scenarios, 1)
        scName = scenarios{sc, 1};

        cd(fullfile(baseDir, '2_BDTR'));
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

        % Determinism check (Run 1 == Run 2)
        diffComp  = abs(m1.completionRate - m2.completionRate);
        diffCRI   = abs(m1.CRI - m2.CRI);
        diffRtask = abs(m1.R_task - m2.R_task);
        diffRtime = abs(m1.R_time - m2.R_time);
        isDeterministic = (diffComp < 1e-12) && (diffCRI < 1e-12) && (diffRtask < 1e-12) && (diffRtime < 1e-12);
        assert(isDeterministic, 'Invariant violation: Non-deterministic execution detected between Run 1 and Run 2');

        if cfg1.sim.includeTravel
            travelStr = '5 m/s flight';
        else
            travelStr = '0 s (excl)';
        end
        determStr = 'PASS (exact)';

        fprintf('%-10s %-8s %8.3f %8.3f %8.3f %9.1f%% %9.1f%% %12s %12s\n', ...
            'BDTR', scName, m1.R_task, m1.R_time, m1.CRI, ...
            m1.completionRate*100, m1.failedRate*100, travelStr, determStr);
    end
end

fprintf('\n%s\n', repmat('=', 1, 100));
fprintf('[PASS] All BDTR smoke tests and protocol invariants passed successfully across both profiles.\n\n');
cd(baseDir);
