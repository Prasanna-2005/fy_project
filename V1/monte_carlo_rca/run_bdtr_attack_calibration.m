%% RUN_BDTR_ATTACK_CALIBRATION
% Consolidates BDTR attack parameter calibration & out-of-sample validation:
%   Stage 1: Systematic calibration sweep on seeds 10001:10030 across
%            attack counts, patterns (random/balanced/directed), and timing windows.
%   Stage 2: Validation of top candidate schedules on strictly disjoint
%            held-out seeds 20001:20030.
%
% Saves outputs to results/csv/ and results/mat/.

clear; clc; close all;
baseDir = fileparts(mfilename('fullpath'));
addpath(baseDir);
addpath(fullfile(baseDir, 'common'));

warnState = warning('off', 'MATLAB:dispatcher:nameConflict');
cleanupWarn = onCleanup(@() warning(warnState));

paperTarget = 82.9;
patterns = {'random', 'balanced', 'directed'};
cd(fullfile(baseDir, 'BDTR'));

%% ======================= STAGE 1: CALIBRATION SWEEP =======================

calibSeeds = 10001:10030;
nCalib = numel(calibSeeds);
windows = {
    [0.15, 0.60], 'mid_15_60';
    [0.10, 0.50], 'early_10_50';
    [0.20, 0.70], 'late_20_70';
    [0.05, 0.35], 'front_05_35'
};

scenarios = {'small', 'large'};
allRows = {};

fprintf('====================================================================================================\n');
fprintf('                    STAGE 1: BDTR ATTACK PROCESS CALIBRATION SWEEP\n');
fprintf('                             (Calibration seeds: %d to %d)\n', min(calibSeeds), max(calibSeeds));
fprintf('====================================================================================================\n\n');

for si = 1:numel(scenarios)
    sc = scenarios{si};
    probeCfg = apply_v2_profile(common_config('bdtr', sc, 1001), 'paper_aligned');
    nSlots = sum(arrayfun(@(u) numel(u.capabilities), probeCfg.uav));
    if strcmp(sc, 'small'), testCounts = 3:7; else, testCounts = 12:18; end

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
                compVec = zeros(nCalib, 1);
                criVec  = zeros(nCalib, 1);

                for ti = 1:nCalib
                    seed = calibSeeds(ti);
                    cfg = apply_v2_profile(common_config('bdtr', sc, seed), 'paper_aligned');
                    cfg.sim.visualize = false;
                    cfg.capabilityChanges = generate_attack_events(cfg, c, pat, seed, w);

                    clear sim;
                    out = sim(cfg, 'bdtr');
                    compVec(ti) = out.metrics.completionRate * 100;
                    criVec(ti)  = out.metrics.CRI;
                end
                resPat.(pat).compMean = mean(compVec);
                resPat.(pat).compStd  = std(compVec);
                resPat.(pat).criMean  = mean(criVec);
            end

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

varNames = {'Scenario', 'AttackCount', 'FractionSlotsLost', 'WindowName', 'WindowMin', 'WindowMax', ...
    'RandomCompMean_pct', 'RandomCompStd_pct', 'RandomCRIMean', ...
    'BalancedCompMean_pct', 'BalancedCompStd_pct', 'BalancedCRIMean', ...
    'DirectedCompMean_pct', 'DirectedCompStd_pct', 'DirectedCRIMean', ...
    'CRIOrderOK', 'DistanceToPaper_pct', 'PaperTarget_pct'};
summary = cell2table(allRows, 'VariableNames', varNames);

legacyRows = cell(height(summary), 8);
for i = 1:height(summary)
    legacyRows(i, :) = { ...
        summary.Scenario(i), summary.AttackCount(i), summary.FractionSlotsLost(i), ...
        summary.RandomCompMean_pct(i), summary.RandomCompStd_pct(i), summary.RandomCompMean_pct(i), ...
        summary.PaperTarget_pct(i), summary.DistanceToPaper_pct(i)};
end
legacySummary = cell2table(legacyRows, 'VariableNames', ...
    {'Scenario', 'AttackCount', 'FractionSlotsLost', 'CompletionMean_pct', ...
     'CompletionStd_pct', 'CompletionMedian_pct', 'PaperTarget_pct', 'DistanceToPaper_pct'});

writetable(summary, resultsFile(baseDir, 'csv', 'bdtr_attack_sensitivity_full.csv'));
writetable(legacySummary, resultsFile(baseDir, 'csv', 'bdtr_attack_count_sensitivity.csv'));
save(resultsFile(baseDir, 'mat', 'bdtr_attack_count_sensitivity.mat'), 'summary', 'legacySummary', 'nCalib', 'paperTarget');

%% ======================= STAGE 2: HELD-OUT VALIDATION =======================

valSeeds = 20001:20030;
nVal = numel(valSeeds);
candidates = {
    'small', 5, [0.15, 0.60], 'S_C5_mid15-60';
    'small', 6, [0.20, 0.70], 'S_C6_late20-70';
    'small', 4, [0.15, 0.60], 'S_C4_mid15-60';
    'large', 18, [0.20, 0.70], 'L_C18_late20-70';
    'large', 16, [0.15, 0.60], 'L_C16_mid15-60';
    'large', 17, [0.20, 0.70], 'L_C17_late20-70'
};

fprintf('====================================================================================================\n');
fprintf('                    STAGE 2: VALIDATION ON FRESH DISJOINT SEEDS (%d to %d)\n', min(valSeeds), max(valSeeds));
fprintf('====================================================================================================\n\n');
fprintf('%-18s %-6s %-12s %8s %8s %8s %8s %8s %8s %10s %8s\n', ...
    'Candidate', 'Count', 'Window', 'Comp_R(%)', 'Comp_B(%)', 'Comp_D(%)', 'CRI_R', 'CRI_B', 'CRI_D', 'DistTo82.9', 'Order_OK');
fprintf('%s\n', repmat('-', 1, 110));

valResults = {};
for cIdx = 1:size(candidates, 1)
    sc     = candidates{cIdx, 1};
    c      = candidates{cIdx, 2};
    w      = candidates{cIdx, 3};
    cLabel = candidates{cIdx, 4};
    wName  = sprintf('[%.2f,%.2f]', w(1), w(2));

    resPat = struct();
    for pi = 1:numel(patterns)
        pat = patterns{pi};
        compVec = zeros(nVal, 1);
        criVec  = zeros(nVal, 1);

        for ti = 1:nVal
            seed = valSeeds(ti);
            cfg = apply_v2_profile(common_config('bdtr', sc, seed), 'paper_aligned');
            cfg.sim.visualize = false;
            cfg.capabilityChanges = generate_attack_events(cfg, c, pat, seed, w);

            clear sim;
            out = sim(cfg, 'bdtr');
            compVec(ti) = out.metrics.completionRate * 100;
            criVec(ti)  = out.metrics.CRI;
        end
        resPat.(pat).compMean = mean(compVec);
        resPat.(pat).compStd  = std(compVec);
        resPat.(pat).criMean  = mean(criVec);
    end

    orderOK = (resPat.random.criMean >= resPat.balanced.criMean) && ...
              (resPat.balanced.criMean >= resPat.directed.criMean);
    distToPaper = abs(resPat.random.compMean - paperTarget);

    fprintf('%-18s %-6d %-12s %8.2f %8.2f %8.2f %8.3f %8.3f %8.3f %10.2f %8s\n', ...
        cLabel, c, wName, resPat.random.compMean, resPat.balanced.compMean, resPat.directed.compMean, ...
        resPat.random.criMean, resPat.balanced.criMean, resPat.directed.criMean, ...
        distToPaper, string(orderOK));

    valResults(end+1, :) = { ...
        string(cLabel), string(sc), c, string(wName), ...
        resPat.random.compMean, resPat.random.compStd, resPat.random.criMean, ...
        resPat.balanced.compMean, resPat.balanced.compStd, resPat.balanced.criMean, ...
        resPat.directed.compMean, resPat.directed.compStd, resPat.directed.criMean, ...
        orderOK, distToPaper}; %#ok<AGROW>
end

cd(baseDir);

valTable = cell2table(valResults, 'VariableNames', ...
    {'Candidate', 'Scenario', 'AttackCount', 'Window', ...
     'RandomCompMean', 'RandomCompStd', 'RandomCRIMean', ...
     'BalancedCompMean', 'BalancedCompStd', 'BalancedCRIMean', ...
     'DirectedCompMean', 'DirectedCompStd', 'DirectedCRIMean', ...
     'CRIOrderOK', 'DistanceToPaper'});

writetable(valTable, resultsFile(baseDir, 'csv', 'bdtr_validation_fresh_seeds.csv'));
save(resultsFile(baseDir, 'mat', 'bdtr_validation_fresh_seeds.mat'), 'valTable', 'valSeeds');
fprintf('\nCalibration & validation complete. Saved results to results/csv/ and results/mat/.\n\n');

function fpath = resultsFile(baseDir, kind, name)
    subDir = fullfile(baseDir, 'results', kind);
    if ~exist(subDir, 'dir')
        mkdir(subDir);
    end
    fpath = fullfile(subDir, name);
end
