%% RUN_V2_REPRODUCTION_BENCHMARK
% Systematic reproduction benchmark (N = 300 runs) across literature baselines
% and local extensions under both paper_aligned and realistic_local profiles.
%
% Profiles:
%   1. 'paper_aligned': Travel disabled (includeTravel = false), deadlines = Inf,
%      calibrated attack schedule. This is the reproduction benchmark.
%   2. 'realistic_local': 5 m/s travel, finite deadlines. Local extension study.
%
% Calibrated Attack Schedule (from systematic calibration sweep):
%   - Small: 6 attacks out of 8 slots (75% loss), timing window [0.20, 0.70]
%   - Large: 18 attacks out of 19 slots (94.7% loss), timing window [0.20, 0.70]

clear; clc; close all;
baseDir = fileparts(mfilename('fullpath'));
addpath(baseDir);
addpath(fullfile(baseDir, 'common'));

warnState = warning('off', 'MATLAB:dispatcher:nameConflict');
cleanupWarn = onCleanup(@() warning(warnState));

nRuns = 300;
profiles = {'paper_aligned', 'realistic_local'};
methods = {
    '1_RRAM', 'rram', 'RRAM';
    '2_BDTR', 'bdtr', 'BDTR';
    '3_SROM', 'srom', 'SROM';
    '5_SABR', 'sabr', 'SABR';
    '6_CARA', 'cara', 'CARA'
};
scenarios = {'small', 'large'};
metricFields = {'R_task', 'R_time', 'CRI', 'throughputRecovery', ...
    'feasibilityRate', 'completionRate', 'failedRate', 'meanCompletionTime'};

nP = numel(profiles); nS = numel(scenarios); nM = size(methods, 1);
nF = numel(metricFields);
data = NaN(nP, nS, nM, nRuns, nF);
total = nP * nS * nM * nRuns; done = 0;

fprintf('====================================================================================================\n');
fprintf('                 V2 FULL BENCHMARK: %d SIMULATIONS (N = %d runs)\n', total, nRuns);
fprintf('                 Profiles: paper_aligned (Reproduction) & realistic_local (Extension)\n');
fprintf('====================================================================================================\n\n');

% Pre-generate attack events for each scenario and run using calibrated schedule
fprintf('Pre-generating attack schedules under Common Random Numbers (CRN)...\n');
allEvents = cell(nS, nRuns);
for si = 1:nS
    sc = scenarios{si};
    if strcmp(sc, 'small')
        nAttacks = 6;
    else
        nAttacks = 18;
    end
    timingWindow = [0.20, 0.70];

    for ri = 1:nRuns
        seed = si * 500000 + ri;
        baseCfg = common_config('bdtr', sc, seed);
        allEvents{si, ri} = generate_attack_events(baseCfg, nAttacks, 'random', seed, timingWindow);
    end
end
fprintf('Attack events pre-generated successfully.\n\n');

tic;
% Loop by method in outer loop to avoid directory switching and clearing inside the hot loop
for mi = 1:nM
    dirName = methods{mi, 1};
    strat   = methods{mi, 2};
    label   = methods{mi, 3};

    cd(fullfile(baseDir, dirName));
    clear sim;
    fprintf('>>> Running Method [%d/%d]: %-12s (%s) <<<\n', mi, nM, label, dirName);

    for pi = 1:nP
        prof = profiles{pi};
        for si = 1:nS
            sc = scenarios{si};
            mStart = tic;

            for ri = 1:nRuns
                seed = si * 500000 + ri;
                cfg = apply_v2_profile(common_config(strat, sc, seed), prof);
                cfg.sim.visualize = false;
                cfg.capabilityChanges = allEvents{si, ri};

                try
                    out = sim(cfg, strat);
                    for fi = 1:nF
                        data(pi, si, mi, ri, fi) = out.metrics.(metricFields{fi});
                    end
                catch ME
                    fprintf(2, '[ERROR] %s/%s/%s run %d: %s\n', prof, sc, label, ri, ME.message);
                end
                done = done + 1;

                if mod(ri, 60) == 0
                    rate = done / toc;
                    remSec = (total - done) / max(0.01, rate);
                    fprintf('    [%s | %s] %3d/%d runs | Overall: %4d/%d (%.1f%%) | %.2f sims/s | ETA: %.0fs\n', ...
                        prof, sc, ri, nRuns, done, total, (done/total)*100, rate, remSec);
                end
            end
        end
    end
    fprintf('\n');
end

cd(baseDir);

% Build summary table
rows = {};
for pi = 1:nP
    for si = 1:nS
        for mi = 1:nM
            vals = squeeze(data(pi, si, mi, :, :));
            rows(end+1, :) = { ...
                string(profiles{pi}), string(scenarios{si}), string(methods{mi, 3}), ...
                mean(vals(:, 6), 'omitnan') * 100, std(vals(:, 6), 0, 'omitnan') * 100, ...
                mean(vals(:, 3), 'omitnan'), std(vals(:, 3), 0, 'omitnan'), ...
                mean(vals(:, 1), 'omitnan'), mean(vals(:, 2), 'omitnan'), ...
                mean(vals(:, 7), 'omitnan') * 100}; %#ok<AGROW>
        end
    end
end
summary = cell2table(rows, 'VariableNames', {'Profile', 'Scenario', 'Algorithm', ...
    'CompletionMean_pct', 'CompletionStd_pct', 'CRIMean', 'CRIStd', 'RtaskMean', 'RtimeMean', 'FailedMean_pct'});

disp('====================================================================================================');
disp('                                   BENCHMARK SUMMARY RESULTS TABLE                                  ');
disp('====================================================================================================');
disp(summary);

% Build raw trial table
rawRows = {};
for pi = 1:nP
    for si = 1:nS
        for mi = 1:nM
            for ri = 1:nRuns
                rawRows(end+1, :) = [{string(profiles{pi}), string(scenarios{si}), string(methods{mi, 3}), ri}, ...
                    num2cell(squeeze(data(pi, si, mi, ri, :))')]; %#ok<AGROW>
            end
        end
    end
end
raw = cell2table(rawRows, 'VariableNames', [{'Profile', 'Scenario', 'Algorithm', 'RunIndex'}, metricFields]);

% Save tables and MAT file
writetable(summary, results_file('csv', 'reproduction_gap_summary.csv'));
writetable(raw, results_file('csv', 'reproduction_gap_raw.csv'));
save(results_file('mat', 'reproduction_gap.mat'), 'data', 'summary', 'raw', 'methods', 'scenarios', 'profiles', 'metricFields', 'nRuns');
fprintf('Saved V2 benchmark results under %s\n', results_paths().root);

% Generate plot cards
try
    plot_summary_scorecards();
    fprintf('Updated summary scorecard plot at results/png/mc_summary_scorecard.png\n');
catch ME
    fprintf(2, 'Plot scorecard generation notice: %s\n', ME.message);
end
