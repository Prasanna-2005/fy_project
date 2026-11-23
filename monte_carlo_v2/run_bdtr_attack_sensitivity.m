%% RUN_V2_BDTR_ATTACK_SENSITIVITY
% BDTR-only attack-count sensitivity. The paper states failure strengths
% but does not publish the concrete event schedule. This reports how the
% paper-aligned local model changes as the exact number of payload losses
% rises, with random event timing in [15%, 60%] of the local horizon.

clear; clc; close all;
baseDir = fileparts(mfilename('fullpath'));
addpath(baseDir); addpath(fullfile(baseDir, 'common'));

nTrials = 30;
scenarios = {'small', 'large'};
paperTarget = 82.9;
rows = {};

for si = 1:numel(scenarios)
    sc = scenarios{si};
    probe = apply_v2_profile(common_config('bdtr', sc, 1), 'paper_aligned');
    nSlots = sum(arrayfun(@(u) numel(u.capabilities), probe.uav));
    fprintf('\n%s: payload slots = %d; %d trials/count\n', upper(sc), nSlots, nTrials);
    for nAttacks = 0:nSlots
        vals = NaN(nTrials, 1);
        for trial = 1:nTrials
            seed = si * 100000 + nAttacks * 1000 + trial;
            cfg = apply_v2_profile(common_config('bdtr', sc, seed), 'paper_aligned');
            cfg.capabilityChanges = generate_attack_events_count(cfg, nAttacks, seed);
            cd(fullfile(baseDir, '2_BDTR')); clear sim
            out = sim(cfg, 'bdtr');
            vals(trial) = out.metrics.completionRate * 100;
        end
        rows(end+1,:) = {string(sc), nAttacks, nAttacks / nSlots, ...
            mean(vals,'omitnan'), std(vals,0,'omitnan'), median(vals,'omitnan'), paperTarget}; %#ok<AGROW>
        fprintf('  attacks %2d/%2d: completion %.2f%%\n', nAttacks, nSlots, mean(vals,'omitnan'));
    end
end
cd(baseDir);
summary = cell2table(rows, 'VariableNames', {'Scenario','AttackCount','FractionSlotsLost', ...
    'CompletionMean_pct','CompletionStd_pct','CompletionMedian_pct','PaperTarget_pct'});
summary.DistanceToPaper_pct = abs(summary.CompletionMean_pct - paperTarget);
disp(summary);
writetable(summary, results_file('csv', 'bdtr_attack_count_sensitivity.csv'));
save(results_file('mat', 'bdtr_attack_count_sensitivity.mat'), 'summary', 'nTrials', 'paperTarget');
