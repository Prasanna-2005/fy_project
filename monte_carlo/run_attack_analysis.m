%% RUN_ATTACK_ANALYSIS  Experiment A: Parametric Attack & Degradation Analysis
%
% Investigates swarm resilience degradation across:
%   - 3 Attack Patterns: Random, Balanced, Directed (Payload-Targeted)
%   - 3 Interruption Strengths: 20%, 30%, 40%
%   - 2 Scenarios: Scenario 1 (Small: 5 UAVs / 80 tasks), Scenario 2 (Large: 10 UAVs / 120 tasks)
%   - 3 Baselines (RRAM, BDTR, SROM) + Our Strategy (Reactive Hungarian)
%
% Produces:
%   1. Degradation curves: CRI and Completion Rate vs. Interruption Strength
%   2. Vulnerability comparison across attack patterns (Directed vs. Random/Balanced)
%   3. Saves data to results/attack_analysis_results.mat and plots to results/attack_degradation_curves.png

clear; clc; close all;

baseDir = fileparts(mfilename('fullpath'));
addpath(fullfile(baseDir, 'common'));

warnState = warning('off', 'MATLAB:dispatcher:nameConflict');
cleanupWarn = onCleanup(@() warning(warnState));

% ---- Methods to evaluate (3 baselines + our strategy) ----
methods = {
    '1_RRAM',          'rram',     'RRAM';
    '2_BDTR',          'bdtr',     'BDTR';
    '3_SROM',          'srom',     'SROM';
    '4_HUNGARIAN',     'reactive', 'Hungarian (Ours)'
};
nMethods = size(methods, 1);

% ---- Scenarios to evaluate ----
scenarios = {
    'small', 'Scenario 1 (Small: 5 UAVs, 2 Payloads, 80 Tasks)';
    'large', 'Scenario 2 (Large: 10 UAVs, 3 Payloads, 120 Tasks)'
};
nScenarios = size(scenarios, 1);

% ---- Experiment A Parameters ----
strengths = [0.20, 0.30, 0.40];
patterns  = {'random', 'balanced', 'directed'};
nStrengths = numel(strengths);
nPatterns  = numel(patterns);

% Number of randomized trials per condition (to average out random attack placement)
nTrials = 10; 

metricFields = {'R_task', 'R_time', 'CRI', 'throughputRecovery', ...
                'feasibilityRate', 'completionRate', 'failedRate', 'meanCompletionTime'};
nMetrics = numel(metricFields);

% Data tensor: [scenarios × methods × patterns × strengths × trials × metrics]
curveData = NaN(nScenarios, nMethods, nPatterns, nStrengths, nTrials, nMetrics);

totalSims = nScenarios * nMethods * nPatterns * nStrengths * nTrials;
simCount = 0;

fprintf('\n=========================================================================================================\n');
fprintf('  EXPERIMENT A: PARAMETRIC ATTACK & DEGRADATION ANALYSIS\n');
fprintf('  %d Scenarios × %d Methods × %d Patterns × %d Strengths × %d Trials = %d Total Simulations\n', ...
    nScenarios, nMethods, nPatterns, nStrengths, nTrials, totalSims);
fprintf('=========================================================================================================\n\n');

tic;

for sc = 1:nScenarios
    scName  = scenarios{sc, 1};
    scLabel = scenarios{sc, 2};
    fprintf('\n>>> Executing %s ...\n', upper(scLabel));

    for pi = 1:nPatterns
        pat = patterns{pi};

        for si = 1:nStrengths
            str = strengths(si);

            for ti = 1:nTrials
                % Deterministic seed per trial condition
                seed = sc * 200000 + pi * 20000 + si * 1000 + ti;

                baseCfg = common_config('rram', scName);
                attackEvents = generate_attack_events(baseCfg, str, pat, seed);

                for mi = 1:nMethods
                    dirName = methods{mi, 1};
                    strat   = methods{mi, 2};

                    trialCfg = common_config(strat, scName);
                    trialCfg.sim.visualize = false;
                    trialCfg.capabilityChanges = attackEvents;

                    cd(fullfile(baseDir, dirName));
                    try
                        res = sim(trialCfg, strat);
                        m = res.metrics;

                        for fi = 1:nMetrics
                            fname = metricFields{fi};
                            if isfield(m, fname)
                                curveData(sc, mi, pi, si, ti, fi) = m.(fname);
                            end
                        end
                    catch ME
                        fprintf('  [ERROR] %s (%s, %s, %d%%) trial %d: %s\n', ...
                            methods{mi, 3}, scName, pat, round(str*100), ti, ME.message);
                    end

                    simCount = simCount + 1;
                end
            end

            elapsed = toc;
            rate = simCount / max(elapsed, 0.01);
            fprintf('    Pattern: %-9s | Strength: %d%% | Completed %d/%d (%.1f sims/s)\n', ...
                pat, round(str*100), simCount, totalSims, rate);
        end
    end
end

cd(baseDir);
elapsed = toc;

%% ======================= DISPLAY DEGRADATION TABLES =======================

fprintf('\n\n=========================================================================================================\n');
fprintf('                       EXPERIMENT A: DEGRADATION CURVE SUMMARY (Mean across trials)\n');
fprintf('=========================================================================================================\n');

criIdx  = find(strcmp(metricFields, 'CRI'));
compIdx = find(strcmp(metricFields, 'completionRate'));

for sc = 1:nScenarios
    scName  = scenarios{sc, 1};
    scLabel = scenarios{sc, 2};

    fprintf('\n---------------------------------------------------------------------------------------------------------\n');
    fprintf('  SCENARIO: %s\n', upper(scLabel));
    fprintf('---------------------------------------------------------------------------------------------------------\n');

    for pi = 1:nPatterns
        pat = patterns{pi};
        fprintf('\n  [Attack Pattern: %s]\n', upper(pat));
        fprintf('  %-12s | %-24s | %-24s\n', 'Method', 'CRI: 20% -> 30% -> 40%', 'CompRate: 20% -> 30% -> 40%');
        fprintf('  %s\n', repmat('-', 1, 68));

        for mi = 1:nMethods
            label = methods{mi, 3};
            criVals  = zeros(1, nStrengths);
            compVals = zeros(1, nStrengths);

            for si = 1:nStrengths
                criVals(si)  = mean(squeeze(curveData(sc, mi, pi, si, :, criIdx)), 'omitnan');
                compVals(si) = mean(squeeze(curveData(sc, mi, pi, si, :, compIdx)), 'omitnan') * 100;
            end

            fprintf('  %-12s |  %.3f  ->  %.3f  ->  %.3f   |  %5.1f%% -> %5.1f%% -> %5.1f%%\n', ...
                label, criVals(1), criVals(2), criVals(3), compVals(1), compVals(2), compVals(3));
        end
    end
end

%% ======================= PLOT DEGRADATION CURVES =======================

try
    hFig = figure('Name', 'Experiment A: Degradation Curves', 'Position', [100, 100, 1200, 700], 'Visible', 'off');
    methodColors = {[0.2, 0.2, 0.2], [0.85, 0.33, 0.1], [0.0, 0.45, 0.74], [0.47, 0.67, 0.19]};
    lineStyles   = {'--', '-', '-.', ':'};
    markers      = {'o', 's', '^', 'd'};

    plotIdx = 1;
    for sc = 1:nScenarios
        scName = scenarios{sc, 1};

        % Subplot for CRI vs. Strength (Directed attack shows steepest collapse)
        subplot(2, 2, plotIdx); hold on; grid on; box on;
        for mi = 1:nMethods
            yCRI = squeeze(mean(curveData(sc, mi, 3, :, :, criIdx), 5, 'omitnan'));
            plot(strengths * 100, yCRI, 'Color', methodColors{mi}, 'LineStyle', lineStyles{mi}, ...
                'Marker', markers{mi}, 'LineWidth', 2, 'MarkerSize', 7, 'DisplayName', methods{mi, 3});
        end
        xlabel('Interruption Strength (%)', 'FontWeight', 'bold');
        ylabel('Comprehensive Resilience Index (CRI)', 'FontWeight', 'bold');
        title(sprintf('%s: CRI under Directed Attack', upper(scName)), 'FontSize', 11);
        ylim([0, 1.05]);
        if plotIdx == 1, legend('Location', 'southwest'); end

        % Subplot for Completion Rate vs. Strength
        subplot(2, 2, plotIdx + 1); hold on; grid on; box on;
        for mi = 1:nMethods
            yComp = squeeze(mean(curveData(sc, mi, 3, :, :, compIdx), 5, 'omitnan')) * 100;
            plot(strengths * 100, yComp, 'Color', methodColors{mi}, 'LineStyle', lineStyles{mi}, ...
                'Marker', markers{mi}, 'LineWidth', 2, 'MarkerSize', 7, 'DisplayName', methods{mi, 3});
        end
        xlabel('Interruption Strength (%)', 'FontWeight', 'bold');
        ylabel('Mission Completion Rate (%)', 'FontWeight', 'bold');
        title(sprintf('%s: Completion Rate under Directed Attack', upper(scName)), 'FontSize', 11);
        ylim([0, 105]);

        plotIdx = plotIdx + 2;
    end

    resultsDir = fullfile(baseDir, 'results');
    if ~exist(resultsDir, 'dir'), mkdir(resultsDir); end
    figPath = fullfile(resultsDir, 'attack_degradation_curves.png');
    saveas(hFig, figPath);
    close(hFig);
    fprintf('\nDegradation curve plots saved to: %s\n', figPath);
catch ME
    fprintf('\n[Note on plotting]: %s\n', ME.message);
end

%% ======================= SAVE RESULTS & TABULAR EXPORTS =======================

% ---- 1. Build Attack Summary Table ----
attackRows = {};
for sc = 1:nScenarios
    scName = scenarios{sc, 1};
    for pi = 1:nPatterns
        pat = patterns{pi};
        for si = 1:nStrengths
            strVal = strengths(si);
            for mi = 1:nMethods
                mLabel = methods{mi, 3};
                row = {string(scName), string(pat), strVal * 100, string(mLabel)};
                for fi = 1:nMetrics
                    vals = squeeze(curveData(sc, mi, pi, si, :, fi));
                    row = [row, {round(mean(vals, 'omitnan'), 4), round(std(vals, 0, 'omitnan'), 4)}]; %#ok<AGROW>
                end
                attackRows(end+1, :) = row; %#ok<AGROW>
            end
        end
    end
end

statVarNames = {'Scenario', 'Pattern', 'Strength_pct', 'Algorithm'};
for fi = 1:nMetrics
    statVarNames = [statVarNames, {[metricFields{fi}, '_Mean']}, {[metricFields{fi}, '_Std']}]; %#ok<AGROW>
end
attackSummaryTable = cell2table(attackRows, 'VariableNames', statVarNames);

% ---- 2. Build Attack Raw Trials Table ----
attackTrialRows = {};
for sc = 1:nScenarios
    scName = scenarios{sc, 1};
    for pi = 1:nPatterns
        pat = patterns{pi};
        for si = 1:nStrengths
            strVal = strengths(si);
            for mi = 1:nMethods
                mLabel = methods{mi, 3};
                for ti = 1:nTrials
                    row = {string(scName), string(pat), strVal * 100, string(mLabel), ti};
                    for fi = 1:nMetrics
                        row = [row, {curveData(sc, mi, pi, si, ti, fi)}]; %#ok<AGROW>
                    end
                    attackTrialRows(end+1, :) = row; %#ok<AGROW>
                end
            end
        end
    end
end
trialVarNames = [{'Scenario', 'Pattern', 'Strength_pct', 'Algorithm', 'TrialIndex'}, metricFields];
attackTrialsTable = cell2table(attackTrialRows, 'VariableNames', trialVarNames);

% ---- 3. Export CSV Files ----
resultsDir = fullfile(baseDir, 'results');
if ~exist(resultsDir, 'dir'), mkdir(resultsDir); end
attackCsvPath       = fullfile(resultsDir, 'attack_summary_metrics.csv');
attackTrialsCsvPath = fullfile(resultsDir, 'attack_raw_trials.csv');
writetable(attackSummaryTable, attackCsvPath);
writetable(attackTrialsTable, attackTrialsCsvPath);

% ---- 4. Save MAT file with tables included ----
attackResults = struct();
attackResults.curveData    = curveData;
attackResults.methods      = methods;
attackResults.scenarios    = scenarios;
attackResults.patterns     = patterns;
attackResults.strengths    = strengths;
attackResults.nTrials      = nTrials;
attackResults.metricFields = metricFields;
attackResults.elapsed      = elapsed;
attackResults.summaryTable = attackSummaryTable;
attackResults.trialsTable  = attackTrialsTable;

matPath = fullfile(resultsDir, 'attack_analysis_results.mat');
save(matPath, 'attackResults', 'attackSummaryTable', 'attackTrialsTable');

fprintf('\nExperiment A results successfully saved to:\n');
fprintf('  - MAT File: %s (includes attackSummaryTable & attackTrialsTable)\n', matPath);
fprintf('  - Summary CSV: %s (open directly in Excel/Sheets)\n', attackCsvPath);
fprintf('  - Raw Trials CSV: %s\n', attackTrialsCsvPath);
fprintf('Total runtime: %.1fs\n\n', elapsed);
