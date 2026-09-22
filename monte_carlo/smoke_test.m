%% SMOKE_TEST  Rapid Developer Sanity-Check (1-Shot Deterministic Run)
%
% Executes a fast, single-iteration headless simulation (~1.5s runtime) across:
%   - All 5 solvers: 1_RRAM, 2_BDTR, 3_SROM, 4_HUNGARIAN, 5_SABR
%   - Both Scenarios: Scenario 1 (Small: 5 UAVs, 80 tasks), Scenario 2 (Large: 10 UAVs, 120 tasks)
%
% PURPOSE:
%   Use this script to rapidly verify that all solver scripts, common configs,
%   and metric evaluators run cleanly without syntax errors or runtime crashes
%   after code modifications.
%
% NOTE FOR EXPERIMENTAL DATA:
%   This is a 1-shot developer sanity-check only.
%   For published, research-grade experimental data and plots, run:
%     1. monte_carlo/run_attack_analysis.m (Parametric attack degradation curves)
%     2. monte_carlo/run_monte_carlo.m     (300-run Monte Carlo statistical benchmark)

clear; clc; close all;

baseDir = fileparts(mfilename('fullpath'));
addpath(fullfile(baseDir, 'common'));

warnState = warning('off', 'MATLAB:dispatcher:nameConflict');
cleanupWarn = onCleanup(@() warning(warnState));

cases = {
    '1_RRAM',          'rram',     'RRAM (Baseline)';
    '2_BDTR',          'bdtr',     'BDTR (Baseline)';
    '3_SROM',          'srom',     'SROM (Baseline)';
    '4_HUNGARIAN',     'reactive', 'Hungarian (Ours)';
    '5_SABR',          'sabr',     'SABR'
};

scenarios = {
    'small', 'Scenario 1 (Small: 5 UAVs, 2 Payloads, 80 Tasks)';
    'large', 'Scenario 2 (Large: 10 UAVs, 3 Payloads, 120 Tasks)'
};

results = struct();

fprintf('\n=========================================================================================================================\n');
fprintf('                           MULTI-UAV BASELINE METHODS SANITY CHECK (RAPID SMOKE TEST)\n');
fprintf('=========================================================================================================================\n');

for sc = 1:size(scenarios, 1)
    scName  = scenarios{sc, 1};
    scLabel = scenarios{sc, 2};

    fprintf('\n── %s ──\n', upper(scLabel));
    fprintf('%-24s %-25s %8s %8s %8s %10s %8s %8s %8s %10s\n', ...
        'Directory', 'Algorithm', 'R_task', 'R_time', 'CRI', 'ThrptRecov', 'FeasRate', 'CompRate', 'FailRate', 'MeanTime(s)');
    fprintf('%s\n', repmat('-', 1, 121));

    for c = 1:size(cases, 1)
        dirName = cases{c, 1};
        strat   = cases{c, 2};
        label   = cases{c, 3};

        cd(fullfile(baseDir, dirName));
        cfg = common_config(strat, scName);
        cfg.sim.visualize = false;

        res = sim(cfg, strat);
        m = res.metrics;
        fieldTag = sprintf('%s_%s', matlab.lang.makeValidName(dirName), scName);
        results.(fieldTag) = res;

        fprintf('%-24s %-25s %8.3f %8.3f %8.3f %10.3f %7.1f%% %7.1f%% %7.1f%% %10.1f\n', ...
            dirName, label, m.R_task, m.R_time, m.CRI, m.throughputRecovery, ...
            m.feasibilityRate*100, m.completionRate*100, m.failedRate*100, m.meanCompletionTime);
    end
end

fprintf('\n%s\n', repmat('=', 1, 121));
fprintf('[PASS] Smoke test completed successfully across all 5 algorithms and 2 scenarios.\n\n');
cd(baseDir);
