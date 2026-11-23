%% MAIN  CARA (Capability-Aware Reallocation)
% Configures the scenario via common_config and runs CARA.

clear; clc; close all;
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'common'));

cfg = common_config('cara');
cfg.sim.visualize = false;

result = sim(cfg, 'cara');

fprintf('\n=== CARA — Result ===\n');
fprintf('%-22s %8s\n', 'Metric', 'Value');
m = result.metrics;
fprintf('%-22s %7.0f%%\n', 'Feasibility rate',       m.feasibilityRate*100);
fprintf('%-22s %7.0f%%\n', 'Completion rate',        m.completionRate*100);
fprintf('%-22s %7.0f%%\n', 'Failed rate',            m.failedRate*100);
fprintf('%-22s %8d\n',     'Reallocation events',    m.reallocationCount);
fprintf('%-22s %8d\n',     'Frozen lost',            m.frozenLost);
fprintf('%-22s %8d\n',     'Unsaved',                m.unsaved);
fprintf('%-22s %8.1f\n',   'Mean completion time(s)', m.meanCompletionTime);
fprintf('%-22s %8.3f\n',   'R_task',                 m.R_task);
fprintf('%-22s %8.3f\n',   'R_time',                 m.R_time);
fprintf('%-22s %8.3f\n',   'CRI',                    m.CRI);
fprintf('%-22s %8.3f\n',   'Throughput recovery',    m.throughputRecovery);
fprintf('%-22s %8.1f\n',   'Median plan (ms)',       m.medianRepairMs);
