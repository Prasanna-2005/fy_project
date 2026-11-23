%% MAIN  SROM (Soft Resource Optimization Method)
% Configures scenario parameters via common_config and executes SROM simulation.

clear; clc; close all;
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'common'));

cfg = common_config('srom');
% Strategy-specific configuration / overrides (if needed):
% cfg.sim.visualize = false; % Uncomment to run fast headless

result = sim(cfg, 'srom');

fprintf('\n=== SROM — Result ===\n');
fprintf('%-22s %8s\n', 'Metric', 'Value');
m = result.metrics;
fprintf('%-22s %7.0f%%\n', 'Feasibility rate',      m.feasibilityRate*100);
fprintf('%-22s %7.0f%%\n', 'Completion rate',        m.completionRate*100);
fprintf('%-22s %7.0f%%\n', 'Failed rate',            m.failedRate*100);
fprintf('%-22s %8d\n',     'Reallocation events',    m.reallocationCount);
fprintf('%-22s %8d\n',     'Preemptions',            m.preemptionCount);
fprintf('%-22s %8.1f\n',   'Mean completion time(s)', m.meanCompletionTime);
