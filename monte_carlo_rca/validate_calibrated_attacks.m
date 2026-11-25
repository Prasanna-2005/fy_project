%% VALIDATE_CALIBRATED_ATTACKS
% Evaluates candidate calibrated attack settings on a strictly DISJOINT validation seed block.
% Calibration block was: seeds 10001:10030
% Fresh Validation block is: seeds 20001:20030 (30 held-out seeds)
%
% This ensures we do not overfit to the calibration seeds.
% Results will be recorded as explicitly calibrated model assumptions.

clear; clc; close all;
baseDir = fileparts(mfilename('fullpath'));
addpath(baseDir);
addpath(fullfile(baseDir, 'common'));

warnState = warning('off', 'MATLAB:dispatcher:nameConflict');
cleanupWarn = onCleanup(@() warning(warnState));

valSeeds = 20001:20030; % 30 disjoint validation seeds
nTrials = numel(valSeeds);
paperTarget = 82.9;

% Candidate configurations from calibration:
% Small candidates:
%   Cand S1: Count 5, mid_15_60 [0.15, 0.60] (Comp ~85.5%)
%   Cand S2: Count 6, late_20_70 [0.20, 0.70] (Comp ~84.0%)
%   Cand S3: Count 4, mid_15_60 [0.15, 0.60] (CRI ordering strictly preserved)
% Large candidates:
%   Cand L1: Count 18, late_20_70 [0.20, 0.70] (Comp ~83.9%, CRI ordering strictly preserved)
%   Cand L2: Count 16, mid_15_60 [0.15, 0.60] (Comp ~85.2%)
%   Cand L3: Count 17, late_20_70 [0.20, 0.70] (Comp ~87.4%, CRI ordering strictly preserved)

candidates = {
    'small', 5, [0.15, 0.60], 'S_C5_mid15-60';
    'small', 6, [0.20, 0.70], 'S_C6_late20-70';
    'small', 4, [0.15, 0.60], 'S_C4_mid15-60';
    'large', 18, [0.20, 0.70], 'L_C18_late20-70';
    'large', 16, [0.15, 0.60], 'L_C16_mid15-60';
    'large', 17, [0.20, 0.70], 'L_C17_late20-70'
};

patterns = {'random', 'balanced', 'directed'};
cd(fullfile(baseDir, '2_BDTR'));

fprintf('====================================================================================================\n');
fprintf('                 VALIDATION ON FRESH DISJOINT SEEDS (Seeds %d to %d)                               \n', min(valSeeds), max(valSeeds));
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
        compVec = zeros(nTrials, 1);
        criVec  = zeros(nTrials, 1);

        for ti = 1:nTrials
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
        resPat.(pat).criStd   = std(criVec);
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

writetable(valTable, results_file('csv', 'bdtr_validation_fresh_seeds.csv'));
save(results_file('mat', 'bdtr_validation_fresh_seeds.mat'), 'valTable', 'valSeeds');
fprintf('\nValidation complete. Saved to %s\n', results_file('csv', 'bdtr_validation_fresh_seeds.csv'));
