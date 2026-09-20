%% RUN_ALL_BASELINES  Run and compare all 4 baseline methods.
% Executes 1_RRAM, 2_BDTR, 3_HUNGARIAN_REACTIVE, and 4_SROM on the
% canonical scenario and prints a comparative summary table.

clear; clc; close all;

baseDir = fileparts(mfilename('fullpath'));
addpath(fullfile(baseDir, 'common'));

warnState = warning('off', 'MATLAB:dispatcher:nameConflict');
cleanupWarn = onCleanup(@() warning(warnState));

cases = {
    '1_RRAM',          'rram',     'RRAM (Baseline)';
    '2_BDTR',          'bdtr',     'BDTR (Baseline)';
    '3_SROM',          'srom',     'SROM (Baseline)';
    '4_HUNGARIAN',     'reactive', 'Hungarian (Ours)'
};

results = struct();

fprintf('\n=========================================================================================================================\n');
fprintf('                                     MULTI-UAV BASELINE METHODS COMPARISON SUMMARY\n');
fprintf('=========================================================================================================================\n');
fprintf('%-24s %-25s %8s %8s %8s %10s %8s %8s %8s %10s\n', ...
    'Directory', 'Algorithm', 'R_task', 'R_time', 'CRI', 'ThrptRecov', 'FeasRate', 'CompRate', 'FailRate', 'MeanTime(s)');
fprintf('%s\n', repmat('-', 1, 121));

for c = 1:size(cases, 1)
    dirName = cases{c, 1};
    strat   = cases{c, 2};
    label   = cases{c, 3};
    
    cd(fullfile(baseDir, dirName));
    cfg = common_config(strat);
    cfg.sim.visualize = false; % Fast mode for batch evaluation
    
    res = sim(cfg, strat);
    m = res.metrics;
    results.(matlab.lang.makeValidName(dirName)) = res;
    
    fprintf('%-24s %-25s %8.3f %8.3f %8.3f %10.3f %7.1f%% %7.1f%% %7.1f%% %10.1f\n', ...
        dirName, label, m.R_task, m.R_time, m.CRI, m.throughputRecovery, ...
        m.feasibilityRate*100, m.completionRate*100, m.failedRate*100, m.meanCompletionTime);
end

fprintf('%s\n', repmat('=', 1, 121));
cd(baseDir);
