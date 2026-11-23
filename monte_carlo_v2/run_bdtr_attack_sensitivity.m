%% RUN_BDTR_ATTACK_SENSITIVITY
% Systematic calibration of the attack process for BDTR under paper_aligned profile.
% Explores:
%   - Attack counts: 3 to 7 (Small), 12 to 18 (Large)
%   - Patterns: random, balanced, directed
%   - Timing windows: [0.15, 0.60], [0.10, 0.50], [0.20, 0.70], [0.05, 0.35]
%
% Goal: Find setting that reproduces BDTR ~0.829 completion and
%       preserves the paper CRI ordering: CRI(random) > CRI(balanced) > CRI(directed).
% Calibration is done on a designated calibration seed block (seeds 10001:10030).

clear; clc; close all;
baseDir = fileparts(mfilename('fullpath'));
addpath(baseDir);
addpath(fullfile(baseDir, 'common'));

warnState = warning('off', 'MATLAB:dispatcher:nameConflict');
cleanupWarn = onCleanup(@() warning(warnState));

calibSeeds = 10001:10030; % 30 calibration seeds
nTrials = numel(calibSeeds);
paperTarget = 82.9;

patterns = {'random', 'balanced', 'directed'};
windows = {
    [0.15, 0.60], 'mid_15_60';
    [0.10, 0.50], 'early_10_50';
    [0.20, 0.70], 'late_20_70';
    [0.05, 0.35], 'front_05_35'
};

scenarios = {'small', 'large'};
allRows = {};
cd(fullfile(baseDir, '2_BDTR'));

fprintf('====================================================================================================\n');
fprintf('                           BDTR ATTACK PROCESS CALIBRATION SWEEP                                    \n');
fprintf('                                (Calibration seeds: %d to %d)                                      \n', min(calibSeeds), max(calibSeeds));
fprintf('====================================================================================================\n\n');

for si = 1:numel(scenarios)
    sc = scenarios{si};
    probeCfg = apply_v2_profile(common_config('bdtr', sc, 1001), 'paper_aligned');
    nSlots = sum(arrayfun(@(u) numel(u.capabilities), probeCfg.uav));

    if strcmp(sc, 'small')
        testCounts = 3:7;
    else
        testCounts = 12:18;
    end

    fprintf('--- SCENARIO: %s (Total slots = %d) ---\n', upper(sc), nSlots);
    fprintf('%-6s %-12s %8s %8s %8s %8s %8s %8s %10s %8s\n', ...
        'Count', 'Window', 'Comp_R(%)', 'Comp_B(%)', 'Comp_D(%)', 'CRI_R', 'CRI_B', 'CRI_D', 'DistTo82.9', 'Order_OK');
    fprintf('%s\n', repmat('-', 1, 95));

    for c = testCounts
        for wi = 1:size(windows, 1)
            w = windows{wi, 1};
            wName = windows{wi, 2};

            resPat = struct();
            for pi = 1:numel(patterns)
                pat = patterns{pi};
                compVec = zeros(nTrials, 1);
                criVec  = zeros(nTrials, 1);
                rtaskVec = zeros(nTrials, 1);
                rtimeVec = zeros(nTrials, 1);

                for ti = 1:nTrials
                    seed = calibSeeds(ti);
                    cfg = apply_v2_profile(common_config('bdtr', sc, seed), 'paper_aligned');
                    cfg.sim.visualize = false;
                    cfg.capabilityChanges = generate_attack_events(cfg, c, pat, seed, w);

                    clear sim;
                    out = sim(cfg, 'bdtr');
                    compVec(ti)  = out.metrics.completionRate * 100;
                    criVec(ti)   = out.metrics.CRI;
                    rtaskVec(ti) = out.metrics.R_task;
                    rtimeVec(ti) = out.metrics.R_time;
                end
                resPat.(pat).compMean = mean(compVec);
                resPat.(pat).compStd  = std(compVec);
                resPat.(pat).criMean  = mean(criVec);
                resPat.(pat).criStd   = std(criVec);
                resPat.(pat).rtaskMean = mean(rtaskVec);
                resPat.(pat).rtimeMean = mean(rtimeVec);
            end

            % Check CRI ordering: random > balanced > directed
            orderOK = (resPat.random.criMean >= resPat.balanced.criMean) && ...
                      (resPat.balanced.criMean >= resPat.directed.criMean);
            distToPaper = abs(resPat.random.compMean - paperTarget);

            fprintf('%-6d %-12s %8.2f %8.2f %8.2f %8.3f %8.3f %8.3f %10.2f %8s\n', ...
                c, wName, resPat.random.compMean, resPat.balanced.compMean, resPat.directed.compMean, ...
                resPat.random.criMean, resPat.balanced.criMean, resPat.directed.criMean, ...
                distToPaper, string(orderOK));

            allRows(end+1, :) = { ...
                string(sc), c, c / nSlots, string(wName), w(1), w(2), ...
                resPat.random.compMean, resPat.random.compStd, resPat.random.criMean, ...
                resPat.balanced.compMean, resPat.balanced.compStd, resPat.balanced.criMean, ...
                resPat.directed.compMean, resPat.directed.compStd, resPat.directed.criMean, ...
                orderOK, distToPaper, paperTarget}; %#ok<AGROW>
        end
    end
    fprintf('\n');
end

cd(baseDir);

varNames = {'Scenario', 'AttackCount', 'FractionSlotsLost', 'WindowName', 'WindowMin', 'WindowMax', ...
    'RandomCompMean_pct', 'RandomCompStd_pct', 'RandomCRIMean', ...
    'BalancedCompMean_pct', 'BalancedCompStd_pct', 'BalancedCRIMean', ...
    'DirectedCompMean_pct', 'DirectedCompStd_pct', 'DirectedCRIMean', ...
    'CRIOrderOK', 'DistanceToPaper_pct', 'PaperTarget_pct'};

summary = cell2table(allRows, 'VariableNames', varNames);

% Also produce legacy-compatible summary table matching results_file schema
legacyRows = {};
for i = 1:height(summary)
    legacyRows(end+1, :) = { ...
        summary.Scenario(i), summary.AttackCount(i), summary.FractionSlotsLost(i), ...
        summary.RandomCompMean_pct(i), summary.RandomCompStd_pct(i), summary.RandomCompMean_pct(i), ...
        summary.PaperTarget_pct(i), summary.DistanceToPaper_pct(i)}; %#ok<AGROW>
end
legacySummary = cell2table(legacyRows, 'VariableNames', ...
    {'Scenario', 'AttackCount', 'FractionSlotsLost', 'CompletionMean_pct', ...
     'CompletionStd_pct', 'CompletionMedian_pct', 'PaperTarget_pct', 'DistanceToPaper_pct'});

writetable(summary, results_file('csv', 'bdtr_attack_sensitivity_full.csv'));
writetable(legacySummary, results_file('csv', 'bdtr_attack_count_sensitivity.csv'));
save(results_file('mat', 'bdtr_attack_count_sensitivity.mat'), 'summary', 'legacySummary', 'nTrials', 'paperTarget');
fprintf('Calibration sweep completed. Saved results to %s\n', results_file('csv', 'bdtr_attack_count_sensitivity.csv'));
