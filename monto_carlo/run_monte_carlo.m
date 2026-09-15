%% RUN_MONTE_CARLO  Full Monte Carlo evaluation of all 4 baseline methods.
%   Runs 10 MC trials × 3 interruption strengths × 3 attack patterns = 90
%   simulations per method (360 total). Collects paper metrics (CRI, R_task,
%   R_time, ThroughputRecovery) and prototype metrics (feasibility, completion,
%   failed rate, mean completion time). Prints summary tables and saves results.

clear; clc; close all;

baseDir = fileparts(mfilename('fullpath'));
addpath(fullfile(baseDir, 'common'));

% Suppress built-in shadowing warning for local sim() function
warnState = warning('off', 'MATLAB:dispatcher:nameConflict');
cleanupWarn = onCleanup(@() warning(warnState));

% ---- Method definitions ----
methods = {
    '1_RRAM',               'rram',     'RRAM';
    '2_BDTR',               'bdtr',     'BDTR';
    '3_HUNGARIAN_REACTIVE', 'reactive', 'Hungarian';
    '4_SROM',               'srom',     'SROM'
};
nMethods = size(methods, 1);

% ---- Load config and MC parameters ----
cfg = common_config('rram'); % base config (strategy overridden per-method)
nRuns     = cfg.mc.nRuns;
strengths = cfg.mc.interruptionStrengths;
patterns  = cfg.mc.attackPatterns;

nStrengths = numel(strengths);
nPatterns  = numel(patterns);

% ---- Metric field names ----
metricFields = {'R_task', 'R_time', 'CRI', 'throughputRecovery', ...
                'feasibilityRate', 'completionRate', 'failedRate', ...
                'meanCompletionTime', 'reallocationCount', 'preemptionCount'};
nMetrics = numel(metricFields);

% ---- Preallocate results: [methods × patterns × strengths × runs × metrics] ----
allResults = NaN(nMethods, nPatterns, nStrengths, nRuns, nMetrics);

totalSims = nMethods * nPatterns * nStrengths * nRuns;
simCount = 0;

fprintf('\n');
fprintf('================================================================================\n');
fprintf('         MONTE CARLO EVALUATION — %d methods × %d patterns × %d strengths × %d runs\n', ...
    nMethods, nPatterns, nStrengths, nRuns);
fprintf('         Total simulations: %d\n', totalSims);
fprintf('================================================================================\n\n');

tic;

for pi = 1:nPatterns
    pat = patterns{pi};
    for si = 1:nStrengths
        str = strengths(si);
        fprintf('── Pattern: %-10s | Strength: %d%% ────────────────────────────\n', ...
            pat, round(str*100));

        for ri = 1:nRuns
            % Deterministic seed: unique per (pattern, strength, run)
            seed = pi * 10000 + si * 100 + ri;

            % Generate attack events for this trial
            baseCfg = common_config('rram');
            attackEvents = generate_attack_events(baseCfg, str, pat, seed);

            for mi = 1:nMethods
                dirName  = methods{mi, 1};
                strat    = methods{mi, 2};
                label    = methods{mi, 3};

                % Configure for this method
                trialCfg = common_config(strat);
                trialCfg.sim.visualize = false; % headless for batch
                trialCfg.capabilityChanges = attackEvents;
                trialCfg.capabilityChange  = attackEvents(1);

                % Run simulation
                cd(fullfile(baseDir, dirName));
                try
                    res = sim(trialCfg, strat);
                    m = res.metrics;

                    % Collect metrics
                    for fi = 1:nMetrics
                        fname = metricFields{fi};
                        if isfield(m, fname)
                            allResults(mi, pi, si, ri, fi) = m.(fname);
                        end
                    end
                catch ME
                    fprintf('  [ERROR] %s run %d: %s\n', label, ri, ME.message);
                end

                simCount = simCount + 1;
            end
        end

        % Print progress
        elapsed = toc;
        rate = simCount / elapsed;
        remaining = (totalSims - simCount) / max(rate, 0.01);
        fprintf('  Completed %d/%d sims (%.1f sims/s, ~%.0fs remaining)\n', ...
            simCount, totalSims, rate, remaining);
    end
end

cd(baseDir);
elapsed = toc;

%% ======================= PRINT SUMMARY TABLES =======================

fprintf('\n\n');
fprintf('================================================================================\n');
fprintf('                    MONTE CARLO RESULTS SUMMARY (mean ± std)\n');
fprintf('                    %d runs per cell | Total time: %.1fs\n', nRuns, elapsed);
fprintf('================================================================================\n');

for pi = 1:nPatterns
    for si = 1:nStrengths
        fprintf('\n─── Attack Pattern: %-10s | Strength: %d%% ───────────────────────\n', ...
            patterns{pi}, round(strengths(si)*100));
        fprintf('%-12s %8s %8s %8s %10s %8s %8s %8s %10s\n', ...
            'Method', 'R_task', 'R_time', 'CRI', 'ThrptRecov', ...
            'FeasRate', 'CompRate', 'FailRate', 'MeanTime');
        fprintf('%s\n', repmat('-', 1, 95));

        for mi = 1:nMethods
            label = methods{mi, 3};
            vals = squeeze(allResults(mi, pi, si, :, :)); % [nRuns × nMetrics]

            means = mean(vals, 1, 'omitnan');
            stds  = std(vals, 0, 1, 'omitnan');

            fprintf('%-12s', label);
            % R_task, R_time, CRI, ThroughputRecovery (indices 1-4)
            for fi = 1:4
                fprintf(' %4.3f±%.2f', means(fi), stds(fi));
            end
            % FeasRate, CompRate, FailRate (indices 5-7, as %)
            for fi = 5:7
                fprintf(' %5.1f%%±%.0f', means(fi)*100, stds(fi)*100);
            end
            % MeanTime (index 8)
            fprintf(' %8.1f±%.1f', means(8), stds(8));
            fprintf('\n');
        end
    end
end

fprintf('\n%s\n', repmat('=', 1, 95));

%% ======================= AGGREGATED ACROSS ALL PATTERNS =======================

fprintf('\n\n');
fprintf('================================================================================\n');
fprintf('              AGGREGATED RESULTS (across all patterns, per strength)\n');
fprintf('================================================================================\n');

for si = 1:nStrengths
    fprintf('\n─── Strength: %d%% (aggregated across %d patterns × %d runs = %d samples) ───\n', ...
        round(strengths(si)*100), nPatterns, nRuns, nPatterns*nRuns);
    fprintf('%-12s %8s %8s %8s %10s %8s %8s %8s %10s\n', ...
        'Method', 'R_task', 'R_time', 'CRI', 'ThrptRecov', ...
        'FeasRate', 'CompRate', 'FailRate', 'MeanTime');
    fprintf('%s\n', repmat('-', 1, 95));

    for mi = 1:nMethods
        label = methods{mi, 3};
        % Aggregate across all patterns for this strength
        vals = squeeze(allResults(mi, :, si, :, :)); % [nPatterns × nRuns × nMetrics]
        vals = reshape(vals, [], nMetrics); % [nPatterns*nRuns × nMetrics]

        means = mean(vals, 1, 'omitnan');
        stds  = std(vals, 0, 1, 'omitnan');

        fprintf('%-12s', label);
        for fi = 1:4
            fprintf(' %4.3f±%.2f', means(fi), stds(fi));
        end
        for fi = 5:7
            fprintf(' %5.1f%%±%.0f', means(fi)*100, stds(fi)*100);
        end
        fprintf(' %8.1f±%.1f', means(8), stds(8));
        fprintf('\n');
    end
end

fprintf('\n%s\n', repmat('=', 1, 95));

%% ======================= SAVE RESULTS =======================

mcResults.allResults   = allResults;
mcResults.methods      = methods;
mcResults.patterns     = patterns;
mcResults.strengths    = strengths;
mcResults.nRuns        = nRuns;
mcResults.metricFields = metricFields;
mcResults.elapsed      = elapsed;

savePath = fullfile(baseDir, 'mc_results.mat');
save(savePath, 'mcResults');
fprintf('\nResults saved to: %s\n', savePath);
fprintf('Total elapsed time: %.1f seconds\n', elapsed);
