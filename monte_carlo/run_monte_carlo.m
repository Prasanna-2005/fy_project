%% RUN_MONTE_CARLO  Experiment B: 300-Run Monte Carlo Benchmark (Table II Scale)
%
% Executes the authentic Monte Carlo protocol from Zeng et al. (2026):
%   - Scenario 1 (Small): 5 UAVs, 2 Payloads, 80 Tasks
%   - Scenario 2 (Large): 10 UAVs, 3 Payloads, 120 Tasks
%   - 3 Baselines (RRAM, BDTR, SROM) + Our Strategy (Reactive Hungarian)
%   - 300 independent stochastic runs per scenario (randomized task generation & failures)
%   - Produces empirical distributions and statistical summaries of:
%       * Mission Completion Rate (Paper: BDTR 0.829, RRAM 0.803, SROM 0.225)
%       * Comprehensive Resilience Index (CRI) (Paper: BDTR 0.862, RRAM 0.347, SROM 0.426)
%       * R_task, R_time, and Throughput Recovery
%
% Saves to results/ subdirectory: mc_distribution_results.mat, mc_distributions.png, CSVs

clear; clc; close all;

baseDir = fileparts(mfilename('fullpath'));
addpath(fullfile(baseDir, 'common'));

warnState = warning('off', 'MATLAB:dispatcher:nameConflict');
cleanupWarn = onCleanup(@() warning(warnState));

% ---- Publication scale: 300 independent runs (set to e.g. 15 for quick testing) ----
nRuns = 300;
if nRuns < 300
    fprintf('\n[NOTE] Running fast check with %d runs (paper scale is 300).\n', nRuns);
end

% ---- Method definitions (3 baselines + our strategy) ----
methods = {
    '1_RRAM',          'rram',     'RRAM';
    '2_BDTR',          'bdtr',     'BDTR';
    '3_SROM',          'srom',     'SROM';
    '4_HUNGARIAN',     'reactive', 'Hungarian (Ours)'
};
nMethods = size(methods, 1);

% ---- Scenario definitions (Table II) ----
scenarios = {
    'small', 'Scenario 1 (Small: 5 UAVs, 2 Payloads, 80 Tasks)';
    'large', 'Scenario 2 (Large: 10 UAVs, 3 Payloads, 120 Tasks)'
};
nScenarios = size(scenarios, 1);

% Nominal interruption strength and pattern for the Monte Carlo protocol
nominalStrength = 0.30; % 30% payload degradation
nominalPattern  = 'random';

metricFields = {'R_task', 'R_time', 'CRI', 'throughputRecovery', ...
                'feasibilityRate', 'completionRate', 'failedRate', 'meanCompletionTime'};
nMetrics = numel(metricFields);

% Tensor: [scenarios × methods × runs × metrics]
mcData = NaN(nScenarios, nMethods, nRuns, nMetrics);

totalSims = nScenarios * nMethods * nRuns;
simCount = 0;

fprintf('\n=========================================================================================================\n');
fprintf('  EXPERIMENT B: MONTE CARLO STATISTICAL BENCHMARK (N = %d Independent Runs)\n', nRuns);
fprintf('  %d Scenarios × %d Methods × %d Runs = %d Total Headless Simulations\n', ...
    nScenarios, nMethods, nRuns, totalSims);
fprintf('=========================================================================================================\n\n');

tic;

for sc = 1:nScenarios
    scName  = scenarios{sc, 1};
    scLabel = scenarios{sc, 2};

    fprintf('\n#########################################################################################################\n');
    fprintf('  BEGINNING %s (%d RUNS)\n', upper(scLabel), nRuns);
    fprintf('#########################################################################################################\n\n');

    for ri = 1:nRuns
        % Deterministic paired seed: each run has unique task placement & failure schedule,
        % but all 4 methods are evaluated on the exact same randomized instance.
        runSeed = sc * 500000 + ri;

        % Generate randomized tasks and environment for this trial
        baseCfg = common_config('rram', scName, runSeed);
        attackEvents = generate_attack_events(baseCfg, nominalStrength, nominalPattern, runSeed);

        for mi = 1:nMethods
            dirName = methods{mi, 1};
            strat   = methods{mi, 2};
            label   = methods{mi, 3};

            trialCfg = common_config(strat, scName, runSeed);
            trialCfg.sim.visualize = false;
            trialCfg.capabilityChanges = attackEvents;

            cd(fullfile(baseDir, dirName));
            try
                res = sim(trialCfg, strat);
                m = res.metrics;

                for fi = 1:nMetrics
                    fname = metricFields{fi};
                    if isfield(m, fname)
                        mcData(sc, mi, ri, fi) = m.(fname);
                    end
                end
            catch ME
                fprintf('  [ERROR] %s (%s) run %d: %s\n', label, scName, ri, ME.message);
            end

            simCount = simCount + 1;
        end

        % Progress update every 10% or at key intervals
        if mod(ri, max(1, round(nRuns / 10))) == 0 || ri == nRuns
            elapsed = toc;
            rate = simCount / max(elapsed, 0.01);
            remaining = (totalSims - simCount) / max(rate, 0.01);
            fprintf('  [%s] Completed run %3d/%d (Total: %4d/%d, %.1f sims/s, ~%.0fs remaining)\n', ...
                scName, ri, nRuns, simCount, totalSims, rate, remaining);
        end
    end
end

cd(baseDir);
elapsed = toc;

%% ======================= PUBLICATION-STYLE STATISTICAL TABLES =======================

fprintf('\n\n=========================================================================================================\n');
fprintf('                 EXPERIMENT B: MONTE CARLO STATISTICAL SUMMARY (N = %d runs)\n', nRuns);
fprintf('                 Total Elapsed Time: %.1fs | Mean Rate: %.1f sims/s\n', elapsed, totalSims / max(elapsed, 0.01));
fprintf('=========================================================================================================\n');

compIdx  = find(strcmp(metricFields, 'completionRate'));
criIdx   = find(strcmp(metricFields, 'CRI'));
rtaskIdx = find(strcmp(metricFields, 'R_task'));
rtimeIdx = find(strcmp(metricFields, 'R_time'));
recovIdx = find(strcmp(metricFields, 'throughputRecovery'));

for sc = 1:nScenarios
    scName  = scenarios{sc, 1};
    scLabel = scenarios{sc, 2};

    fprintf('\n=========================================================================================================\n');
    fprintf('  SCENARIO: %s\n', upper(scLabel));
    fprintf('=========================================================================================================\n');
    fprintf('%-12s | %-16s | %-16s | %-16s | %-16s | %-16s\n', ...
        'Method', 'CompletionRate', 'CRI (Resilience)', 'R_task', 'R_time', 'ThroughputRecov');
    fprintf('%-12s | %-16s | %-16s | %-16s | %-16s | %-16s\n', ...
        '', 'mean ± std [med]', 'mean ± std [med]', 'mean ± std [med]', 'mean ± std [med]', 'mean ± std [med]');
    fprintf('%s\n', repmat('-', 1, 98));

    for mi = 1:nMethods
        label = methods{mi, 3};

        % Extract arrays
        compVals  = squeeze(mcData(sc, mi, :, compIdx));
        criVals   = squeeze(mcData(sc, mi, :, criIdx));
        rtaskVals = squeeze(mcData(sc, mi, :, rtaskIdx));
        rtimeVals = squeeze(mcData(sc, mi, :, rtimeIdx));
        recovVals = squeeze(mcData(sc, mi, :, recovIdx));

        fprintf('%-12s | %5.1f%%±%4.1f%% [%4.1f%%] | %4.3f±%4.3f [%4.3f] | %4.3f±%4.3f [%4.3f] | %4.3f±%4.3f [%4.3f] | %4.3f±%4.3f [%4.3f]\n', ...
            label, ...
            mean(compVals, 'omitnan')*100, std(compVals, 0, 'omitnan')*100, median(compVals, 'omitnan')*100, ...
            mean(criVals, 'omitnan'), std(criVals, 0, 'omitnan'), median(criVals, 'omitnan'), ...
            mean(rtaskVals, 'omitnan'), std(rtaskVals, 0, 'omitnan'), median(rtaskVals, 'omitnan'), ...
            mean(rtimeVals, 'omitnan'), std(rtimeVals, 0, 'omitnan'), median(rtimeVals, 'omitnan'), ...
            mean(recovVals, 'omitnan'), std(recovVals, 0, 'omitnan'), median(recovVals, 'omitnan'));
    end

    % Paper comparison note
    fprintf('%s\n', repmat('-', 1, 98));
    fprintf('  * Paper Reported Targets (Zeng et al. 2026 Table II / Abstract):\n');
    fprintf('    - BDTR: CompRate = 82.9%%, CRI = 0.862\n');
    fprintf('    - RRAM: CompRate = 80.3%%, CRI = 0.347\n');
    fprintf('    - SROM: CompRate = 22.5%%, CRI = 0.426\n');
end

%% ======================= PLOT MONTE CARLO DISTRIBUTIONS =======================

try
    hFig = figure('Name', 'Experiment B: Monte Carlo Distributions', 'Position', [100, 100, 1200, 750], 'Visible', 'off');
    methodLabels = methods(:, 3);
    xPos = 1:nMethods;

    plotIdx = 1;
    for sc = 1:nScenarios
        scName = scenarios{sc, 1};

        % Plot 1: Completion Rate (Mean ± Std with trial scatter)
        subplot(2, 2, plotIdx); hold on; grid on; box on;
        compMatrix = squeeze(mcData(sc, :, :, compIdx)) * 100; % [nMethods × nRuns]
        meansComp = mean(compMatrix, 2, 'omitnan');
        stdsComp  = std(compMatrix, 0, 2, 'omitnan');

        b1 = bar(xPos, meansComp, 0.55, 'FaceColor', [0.3, 0.55, 0.85], 'EdgeColor', 'none', 'FaceAlpha', 0.85);
        errorbar(xPos, meansComp, stdsComp, 'k.', 'LineWidth', 1.8, 'CapSize', 10);
        set(gca, 'XTick', xPos, 'XTickLabel', methodLabels, 'FontSize', 10);
        ylabel('Mission Completion Rate (%)', 'FontWeight', 'bold');
        title(sprintf('%s: Completion Rate (N=%d runs)', upper(scName), nRuns), 'FontSize', 11);
        ylim([0, 105]);

        % Plot 2: CRI (Mean ± Std with trial scatter)
        subplot(2, 2, plotIdx + 1); hold on; grid on; box on;
        criMatrix = squeeze(mcData(sc, :, :, criIdx)); % [nMethods × nRuns]
        meansCRI = mean(criMatrix, 2, 'omitnan');
        stdsCRI  = std(criMatrix, 0, 2, 'omitnan');

        b2 = bar(xPos, meansCRI, 0.55, 'FaceColor', [0.85, 0.45, 0.3], 'EdgeColor', 'none', 'FaceAlpha', 0.85);
        errorbar(xPos, meansCRI, stdsCRI, 'k.', 'LineWidth', 1.8, 'CapSize', 10);
        set(gca, 'XTick', xPos, 'XTickLabel', methodLabels, 'FontSize', 10);
        ylabel('Comprehensive Resilience Index (CRI)', 'FontWeight', 'bold');
        title(sprintf('%s: CRI Resilience (N=%d runs)', upper(scName), nRuns), 'FontSize', 11);
        ylim([0, 1.05]);

        plotIdx = plotIdx + 2;
    end

    resultsDir = fullfile(baseDir, 'results');
    if ~exist(resultsDir, 'dir'), mkdir(resultsDir); end
    figPath = fullfile(resultsDir, 'mc_distributions.png');
    saveas(hFig, figPath);
    close(hFig);
    fprintf('\nMonte Carlo distribution plots successfully saved to: %s\n', figPath);
catch ME
    fprintf('\n[Note on plotting]: %s\n', ME.message);
end

%% ======================= SAVE DATA & TABULAR EXPORTS =======================

% ---- 1. Build Summary Table (Mean ± Std and Median across runs) ----
summaryRows = {};
for sc = 1:nScenarios
    scName = scenarios{sc, 1};
    for mi = 1:nMethods
        mLabel = methods{mi, 3};
        
        compVals  = squeeze(mcData(sc, mi, :, compIdx)) * 100;
        criVals   = squeeze(mcData(sc, mi, :, criIdx));
        rtaskVals = squeeze(mcData(sc, mi, :, rtaskIdx));
        rtimeVals = squeeze(mcData(sc, mi, :, rtimeIdx));
        recovVals = squeeze(mcData(sc, mi, :, recovIdx));

        summaryRows(end+1, :) = { ...
            string(scName), string(mLabel), ...
            round(mean(compVals, 'omitnan'), 2), round(std(compVals, 0, 'omitnan'), 2), round(median(compVals, 'omitnan'), 2), ...
            round(mean(criVals, 'omitnan'), 3), round(std(criVals, 0, 'omitnan'), 3), round(median(criVals, 'omitnan'), 3), ...
            round(mean(rtaskVals, 'omitnan'), 3), round(std(rtaskVals, 0, 'omitnan'), 3), round(median(rtaskVals, 'omitnan'), 3), ...
            round(mean(rtimeVals, 'omitnan'), 3), round(std(rtimeVals, 0, 'omitnan'), 3), round(median(rtimeVals, 'omitnan'), 3), ...
            round(mean(recovVals, 'omitnan'), 3), round(std(recovVals, 0, 'omitnan'), 3), round(median(recovVals, 'omitnan'), 3) ...
        }; %#ok<AGROW>
    end
end

mcSummaryTable = cell2table(summaryRows, 'VariableNames', { ...
    'Scenario', 'Algorithm', ...
    'CompRate_Mean_pct', 'CompRate_Std_pct', 'CompRate_Med_pct', ...
    'CRI_Mean', 'CRI_Std', 'CRI_Med', ...
    'R_task_Mean', 'R_task_Std', 'R_task_Med', ...
    'R_time_Mean', 'R_time_Std', 'R_time_Med', ...
    'ThrptRecov_Mean', 'ThrptRecov_Std', 'ThrptRecov_Med' ...
});

% ---- 2. Build Raw Trials Table (Flattened per-run records) ----
trialRows = {};
for sc = 1:nScenarios
    scName = scenarios{sc, 1};
    for mi = 1:nMethods
        mLabel = methods{mi, 3};
        for ri = 1:nRuns
            row = {string(scName), string(mLabel), ri};
            for fi = 1:nMetrics
                row = [row, {mcData(sc, mi, ri, fi)}]; %#ok<AGROW>
            end
            trialRows(end+1, :) = row; %#ok<AGROW>
        end
    end
end

trialVarNames = [{'Scenario', 'Algorithm', 'RunIndex'}, metricFields];
mcTrialsTable = cell2table(trialRows, 'VariableNames', trialVarNames);

% ---- 3. Export CSV Files for instant opening in Excel / VS Code ----
resultsDir = fullfile(baseDir, 'results');
if ~exist(resultsDir, 'dir'), mkdir(resultsDir); end
summaryCsvPath = fullfile(resultsDir, 'mc_summary_metrics.csv');
trialsCsvPath  = fullfile(resultsDir, 'mc_raw_trials.csv');
writetable(mcSummaryTable, summaryCsvPath);
writetable(mcTrialsTable, trialsCsvPath);

% ---- 4. Save to .mat with tables included as top-level workspace variables ----
mcDistributionResults = struct();
mcDistributionResults.mcData          = mcData;
mcDistributionResults.methods         = methods;
mcDistributionResults.scenarios       = scenarios;
mcDistributionResults.nominalStrength = nominalStrength;
mcDistributionResults.nominalPattern  = nominalPattern;
mcDistributionResults.nRuns           = nRuns;
mcDistributionResults.metricFields    = metricFields;
mcDistributionResults.elapsed         = elapsed;
mcDistributionResults.summaryTable    = mcSummaryTable;
mcDistributionResults.trialsTable     = mcTrialsTable;

savePath = fullfile(resultsDir, 'mc_distribution_results.mat');
save(savePath, 'mcDistributionResults', 'mcSummaryTable', 'mcTrialsTable');

fprintf('\nMonte Carlo distribution results successfully saved to:\n');
fprintf('  - MAT File: %s (includes mcSummaryTable & mcTrialsTable)\n', savePath);
fprintf('  - Summary CSV: %s (open directly in Excel/Sheets)\n', summaryCsvPath);
fprintf('  - Raw Trials CSV: %s\n', trialsCsvPath);
fprintf('Total runtime: %.1f seconds\n\n', elapsed);
