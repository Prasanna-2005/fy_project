%% MAIN  SABR (State-Aware Bidirectional Reallocation)
% Phase 1: Reactive Hungarian. Phase 2: deadline-aware residual transfers.

clear; clc; close all;
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'common'));

cfg = common_config('sabr');

result = sim(cfg, 'sabr');

fprintf('\n=== SABR — Result ===\n');
fprintf('%-22s %8s\n', 'Metric', 'Value');
m = result.metrics;
fprintf('%-22s %7.0f%%\n', 'Feasibility rate',      m.feasibilityRate*100);
fprintf('%-22s %7.0f%%\n', 'Completion rate',        m.completionRate*100);
fprintf('%-22s %7.0f%%\n', 'Failed rate',            m.failedRate*100);
fprintf('%-22s %8d\n',     'Reallocation events',    m.reallocationCount);
fprintf('%-22s %8d\n',     'Preemptions',            m.preemptionCount);
fprintf('%-22s %8d\n',     'Phase-2 transfers',      m.phase2Count);
fprintf('%-22s %8.1f\n',   'Mean completion time(s)', m.meanCompletionTime);
fprintf('%-22s %8.3f\n',   'R_task (Resilience)',    m.R_task);
fprintf('%-22s %8.3f\n',   'R_time (Time efficiency)', m.R_time);
fprintf('%-22s %8.3f\n',   'CRI (Comprehensive)',    m.CRI);
fprintf('%-22s %8.3f\n',   'Throughput Recovery',    m.throughputRecovery);
