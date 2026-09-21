%% INSPECT_RESULTS  Easy Viewer & Exporter for Monte Carlo & Attack Analysis Results
%
% This utility lets you easily inspect and view all computed metrics without
% wrestling with multidimensional arrays or raw .mat file indexing.
%
% Features:
%   1. Loads mc_distribution_results.mat and displays clean summary tables.
%   2. Loads attack_analysis_results.mat and displays degradation comparison tables.
%   3. Automatically generates/refreshes human-readable CSV files for viewing in Excel:
%        - csv/mc_summary_metrics.csv (Monte Carlo means, stds, medians)
%        - csv/mc_raw_trials.csv     (All individual stochastic runs)
%        - csv/attack_summary_metrics.csv (Degradation sweeps across patterns & strengths)
%   4. Refreshes two summary-scorecard images (one per experiment):
%        - png/mc_summary_scorecard.png
%        - png/attack_summary_scorecard.png
%
% USAGE:
%   inspect_results         % Inspect everything
%   inspect_results('mc')   % Inspect Monte Carlo benchmark only
%   inspect_results('atk')  % Inspect Attack Analysis only

function inspect_results(whichExp)
    if nargin < 1 || isempty(whichExp)
        whichExp = 'all';
    end

    baseDir = fileparts(mfilename('fullpath'));
    addpath(baseDir);
    results_paths();
    fprintf('\n=========================================================================================================\n');
    fprintf('                          MULTI-UAV RESILIENCE METRICS INSPECTION REPORT\n');
    fprintf('=========================================================================================================\n');

    %% ------------------- 1. MONTE CARLO BENCHMARK (EXPERIMENT B) -------------------
    if ismember(lower(whichExp), {'all', 'mc', 'monte_carlo'})
        mcMatPath = results_locate('mat', 'mc_distribution_results.mat');
        if exist(mcMatPath, 'file')
            fprintf('\n>>> [EXPERIMENT B: MONTE CARLO BENCHMARK]\n');
            mcDataStruct = load(mcMatPath);
            d = mcDataStruct.mcDistributionResults;

            scenarios    = d.scenarios;
            methods      = d.methods;
            metricFields = d.metricFields;
            mcData       = d.mcData;
            nSc          = size(scenarios, 1);
            nM           = size(methods, 1);
            nRuns        = d.nRuns;

            compIdx  = find(strcmp(metricFields, 'completionRate'));
            criIdx   = find(strcmp(metricFields, 'CRI'));
            rtaskIdx = find(strcmp(metricFields, 'R_task'));
            rtimeIdx = find(strcmp(metricFields, 'R_time'));
            recovIdx = find(strcmp(metricFields, 'throughputRecovery'));

            summaryRows = {};
            for sc = 1:nSc
                scName  = scenarios{sc, 1};
                scLabel = scenarios{sc, 2};
                fprintf('\n  Scenario: %s (N = %d runs, Nominal 30%% Random Attack)\n', upper(scLabel), nRuns);
                fprintf('  %-12s | %-15s | %-14s | %-14s | %-14s | %-14s\n', ...
                    'Algorithm', 'CompletionRate', 'CRI', 'R_task', 'R_time', 'ThrptRecov');
                fprintf('  %-12s | %-15s | %-14s | %-14s | %-14s | %-14s\n', ...
                    '', 'mean±std [med]', 'mean±std [med]', 'mean±std [med]', 'mean±std [med]', 'mean±std [med]');
                fprintf('  %s\n', repmat('-', 1, 95));

                for mi = 1:nM
                    mLabel   = methods{mi, 3};
                    compVals = squeeze(mcData(sc, mi, :, compIdx)) * 100;
                    criVals  = squeeze(mcData(sc, mi, :, criIdx));
                    rtVals   = squeeze(mcData(sc, mi, :, rtaskIdx));
                    rtimeV   = squeeze(mcData(sc, mi, :, rtimeIdx));
                    recovV   = squeeze(mcData(sc, mi, :, recovIdx));

                    fprintf('  %-12s | %5.1f%%±%4.1f%%[%4.1f%%] | %4.3f±%4.3f[%4.3f] | %4.3f±%4.3f[%4.3f] | %4.3f±%4.3f[%4.3f] | %4.3f±%4.3f[%4.3f]\n', ...
                        mLabel, ...
                        mean(compVals, 'omitnan'), std(compVals, 0, 'omitnan'), median(compVals, 'omitnan'), ...
                        mean(criVals, 'omitnan'), std(criVals, 0, 'omitnan'), median(criVals, 'omitnan'), ...
                        mean(rtVals, 'omitnan'), std(rtVals, 0, 'omitnan'), median(rtVals, 'omitnan'), ...
                        mean(rtimeV, 'omitnan'), std(rtimeV, 0, 'omitnan'), median(rtimeV, 'omitnan'), ...
                        mean(recovV, 'omitnan'), std(recovV, 0, 'omitnan'), median(recovV, 'omitnan'));

                    summaryRows(end+1, :) = { ...
                        string(scName), string(mLabel), ...
                        round(mean(compVals, 'omitnan'), 2), round(std(compVals, 0, 'omitnan'), 2), round(median(compVals, 'omitnan'), 2), ...
                        round(mean(criVals, 'omitnan'), 3), round(std(criVals, 0, 'omitnan'), 3), round(median(criVals, 'omitnan'), 3), ...
                        round(mean(rtVals, 'omitnan'), 3), round(std(rtVals, 0, 'omitnan'), 3), round(median(rtVals, 'omitnan'), 3), ...
                        round(mean(rtimeV, 'omitnan'), 3), round(std(rtimeV, 0, 'omitnan'), 3), round(median(rtimeV, 'omitnan'), 3), ...
                        round(mean(recovV, 'omitnan'), 3), round(std(recovV, 0, 'omitnan'), 3), round(median(recovV, 'omitnan'), 3) ...
                    }; %#ok<AGROW>
                end
            end

            % Ensure CSV files exist
            mcSummaryTable = cell2table(summaryRows, 'VariableNames', { ...
                'Scenario', 'Algorithm', ...
                'CompRate_Mean_pct', 'CompRate_Std_pct', 'CompRate_Med_pct', ...
                'CRI_Mean', 'CRI_Std', 'CRI_Med', ...
                'R_task_Mean', 'R_task_Std', 'R_task_Med', ...
                'R_time_Mean', 'R_time_Std', 'R_time_Med', ...
                'ThrptRecov_Mean', 'ThrptRecov_Std', 'ThrptRecov_Med' ...
            });
            mcCsvPath = results_file('csv', 'mc_summary_metrics.csv');
            writetable(mcSummaryTable, mcCsvPath);

            % Build raw trials table
            trialRows = {};
            for sc = 1:nSc
                scName = scenarios{sc, 1};
                for mi = 1:nM
                    mLabel = methods{mi, 3};
                    for ri = 1:nRuns
                        row = {string(scName), string(mLabel), ri};
                        for fi = 1:numel(metricFields)
                            row = [row, {mcData(sc, mi, ri, fi)}]; %#ok<AGROW>
                        end
                        trialRows(end+1, :) = row; %#ok<AGROW>
                    end
                end
            end
            trialVarNames = [{'Scenario', 'Algorithm', 'RunIndex'}, metricFields];
            mcTrialsTable = cell2table(trialRows, 'VariableNames', trialVarNames);
            trialsCsvPath = results_file('csv', 'mc_raw_trials.csv');
            writetable(mcTrialsTable, trialsCsvPath);

            % Update mat file if needed
            mcDistributionResults = d;
            mcDistributionResults.summaryTable = mcSummaryTable;
            mcDistributionResults.trialsTable  = mcTrialsTable;
            save(mcMatPath, 'mcDistributionResults', 'mcSummaryTable', 'mcTrialsTable');

            fprintf('\n  Files generated/updated for instant access:\n');
            fprintf('    -> %s (Open in Excel or MATLAB)\n', mcCsvPath);
            fprintf('    -> %s (Full individual trial breakdown)\n', trialsCsvPath);
        else
            fprintf('\n[EXPERIMENT B] mc_distribution_results.mat not found. Run monte_carlo/run_monte_carlo.m first.\n');
        end
    end

    %% ------------------- 2. ATTACK ANALYSIS (EXPERIMENT A) -------------------
    if ismember(lower(whichExp), {'all', 'atk', 'attack'})
        atkMatPath = results_locate('mat', 'attack_analysis_results.mat');
        if exist(atkMatPath, 'file')
            fprintf('\n\n>>> [EXPERIMENT A: PARAMETRIC ATTACK ANALYSIS]\n');
            atkDataStruct = load(atkMatPath);
            a = atkDataStruct.attackResults;

            scenarios    = a.scenarios;
            methods      = a.methods;
            patterns     = a.patterns;
            strengths    = a.strengths;
            curveData    = a.curveData;
            metricFields = a.metricFields;
            nSc          = size(scenarios, 1);
            nM           = size(methods, 1);
            nP           = numel(patterns);
            nS           = numel(strengths);

            compIdx = find(strcmp(metricFields, 'completionRate'));
            criIdx  = find(strcmp(metricFields, 'CRI'));

            attackRows = {};
            for sc = 1:nSc
                scLabel = scenarios{sc, 2};
                fprintf('\n  Scenario: %s\n', upper(scLabel));

                for pi = 1:nP
                    pat = patterns{pi};
                    fprintf('  [Attack Pattern: %s]\n', upper(pat));
                    fprintf('  %-12s | %-24s | %-24s\n', 'Algorithm', 'CRI: 20% -> 30% -> 40%', 'CompRate: 20% -> 30% -> 40%');
                    fprintf('  %s\n', repmat('-', 1, 68));

                    for mi = 1:nM
                        mLabel   = methods{mi, 3};
                        criVals  = zeros(1, nS);
                        compVals = zeros(1, nS);

                        for si = 1:nS
                            criVals(si)  = mean(squeeze(curveData(sc, mi, pi, si, :, criIdx)), 'omitnan');
                            compVals(si) = mean(squeeze(curveData(sc, mi, pi, si, :, compIdx)), 'omitnan') * 100;
                        end

                        fprintf('  %-12s |  %.3f  ->  %.3f  ->  %.3f   |  %5.1f%% -> %5.1f%% -> %5.1f%%\n', ...
                            mLabel, criVals(1), criVals(2), criVals(3), compVals(1), compVals(2), compVals(3));
                    end
                end
            end

            % Build attack summary table
            for sc = 1:nSc
                scName = scenarios{sc, 1};
                for pi = 1:nP
                    pat = patterns{pi};
                    for si = 1:nS
                        strVal = strengths(si);
                        for mi = 1:nM
                            mLabel = methods{mi, 3};
                            row = {string(scName), string(pat), strVal * 100, string(mLabel)};
                            for fi = 1:numel(metricFields)
                                vals = squeeze(curveData(sc, mi, pi, si, :, fi));
                                row = [row, {round(mean(vals, 'omitnan'), 4), round(std(vals, 0, 'omitnan'), 4)}]; %#ok<AGROW>
                            end
                            attackRows(end+1, :) = row; %#ok<AGROW>
                        end
                    end
                end
            end
            statVarNames = {'Scenario', 'Pattern', 'Strength_pct', 'Algorithm'};
            for fi = 1:numel(metricFields)
                statVarNames = [statVarNames, {[metricFields{fi}, '_Mean']}, {[metricFields{fi}, '_Std']}]; %#ok<AGROW>
            end
            attackSummaryTable = cell2table(attackRows, 'VariableNames', statVarNames);
            attackCsvPath = results_file('csv', 'attack_summary_metrics.csv');
            writetable(attackSummaryTable, attackCsvPath);

            % Build attack raw trials table
            attackTrialRows = {};
            nTrials = size(curveData, 5);
            for sc = 1:nSc
                scName = scenarios{sc, 1};
                for pi = 1:nP
                    pat = patterns{pi};
                    for si = 1:nS
                        strVal = strengths(si);
                        for mi = 1:nM
                            mLabel = methods{mi, 3};
                            for ti = 1:nTrials
                                row = {string(scName), string(pat), strVal * 100, string(mLabel), ti};
                                for fi = 1:numel(metricFields)
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
            attackTrialsCsvPath = results_file('csv', 'attack_raw_trials.csv');
            writetable(attackTrialsTable, attackTrialsCsvPath);

            attackResults = a;
            attackResults.summaryTable = attackSummaryTable;
            attackResults.trialsTable  = attackTrialsTable;
            save(atkMatPath, 'attackResults', 'attackSummaryTable', 'attackTrialsTable');

            fprintf('\n  Files generated/updated for instant access:\n');
            fprintf('    -> %s (Open in Excel or MATLAB)\n', attackCsvPath);
            fprintf('    -> %s (Full individual trial breakdown)\n', attackTrialsCsvPath);
        else
            fprintf('\n[EXPERIMENT A] attack_analysis_results.mat not found. Run monte_carlo/run_attack_analysis.m first.\n');
        end
    end

    try
        plot_summary_scorecards();
    catch ME
        fprintf('\n[Note on scorecard plots]: %s\n', ME.message);
    end

    fprintf('\n=========================================================================================================\n');
    fprintf('  HOW TO ACCESS IN MATLAB:\n');
    fprintf('    1. Load data: load("monte_carlo/results/mat/mc_distribution_results.mat")\n');
    fprintf('    2. View table in MATLAB: openvar("mcSummaryTable")\n');
    fprintf('    3. Open in Excel: double-click results/csv/mc_summary_metrics.csv\n');
    fprintf('=========================================================================================================\n\n');
end
