%% RUN_V2_REPRODUCTION_BENCHMARK
% Separate the paper-constraint-aligned benchmark from the local realistic
% extension. This is a comparison study, not an exact paper reproduction:
% the paper omits task geometry, execution-time distribution, horizon, and
% payload-failure event schedule.

clear; clc; close all;
baseDir = fileparts(mfilename('fullpath'));
addpath(baseDir);
addpath(fullfile(baseDir, 'common'));

nRuns = 300;
profiles = {'paper_aligned', 'realistic_local'};
methods = {
    '1_RRAM', 'rram', 'RRAM';
    '2_BDTR', 'bdtr', 'BDTR';
    '3_SROM', 'srom', 'SROM';
    '5_SABR', 'sabr', 'SABR';
    '6_CARA', 'cara', 'CARA'};
scenarios = {'small', 'large'};
metricFields = {'R_task', 'R_time', 'CRI', 'throughputRecovery', ...
    'feasibilityRate', 'completionRate', 'failedRate', 'meanCompletionTime'};

nP = numel(profiles); nS = numel(scenarios); nM = size(methods, 1);
nF = numel(metricFields);
data = NaN(nP, nS, nM, nRuns, nF);
total = nP * nS * nM * nRuns; done = 0;

fprintf('V2 REPRODUCTION-GAP BENCHMARK: %d simulations\n', total);
fprintf('Profiles: paper_aligned (no flight/deadlines), realistic_local (legacy assumptions).\n');
tic;
for pi = 1:nP
    for si = 1:nS
        for ri = 1:nRuns
            % Same seed across profiles: their difference is only the
            % explicitly declared deadline/travel assumption.
            seed = si * 500000 + ri;
            baseCfg = apply_v2_profile(common_config('rram', scenarios{si}, seed), profiles{pi});
            events = generate_attack_events(baseCfg, 0.30, 'random', seed);
            for mi = 1:nM
                cfg = apply_v2_profile(common_config(methods{mi,2}, scenarios{si}, seed), profiles{pi});
                cfg.sim.visualize = false;
                cfg.capabilityChanges = events;
                cd(fullfile(baseDir, methods{mi,1}));
                clear sim
                try
                    out = sim(cfg, methods{mi,2});
                    for fi = 1:nF
                        data(pi,si,mi,ri,fi) = out.metrics.(metricFields{fi});
                    end
                catch ME
                    fprintf(2, '[ERROR] %s/%s/%s run %d: %s\n', profiles{pi}, scenarios{si}, methods{mi,3}, ri, ME.message);
                end
                done = done + 1;
            end
            if mod(ri, 30) == 0
                fprintf('  %s | %s | run %d/%d | %.1f sims/s\n', profiles{pi}, scenarios{si}, ri, nRuns, done/toc);
            end
        end
    end
end
cd(baseDir);

rows = {};
for pi = 1:nP
    for si = 1:nS
        for mi = 1:nM
            vals = squeeze(data(pi,si,mi,:,:));
            rows(end+1,:) = {string(profiles{pi}), string(scenarios{si}), string(methods{mi,3}), ...
                mean(vals(:,6),'omitnan') * 100, std(vals(:,6),0,'omitnan') * 100, ...
                mean(vals(:,3),'omitnan'), std(vals(:,3),0,'omitnan'), ...
                mean(vals(:,1),'omitnan'), mean(vals(:,2),'omitnan'), ...
                mean(vals(:,7),'omitnan') * 100}; %#ok<AGROW>
        end
    end
end
summary = cell2table(rows, 'VariableNames', {'Profile','Scenario','Algorithm', ...
    'CompletionMean_pct','CompletionStd_pct','CRIMean','CRIStd','RtaskMean','RtimeMean','FailedMean_pct'});
disp(summary);

rawRows = {};
for pi = 1:nP
    for si = 1:nS
        for mi = 1:nM
            for ri = 1:nRuns
                rawRows(end+1,:) = [{string(profiles{pi}), string(scenarios{si}), string(methods{mi,3}), ri}, ...
                    num2cell(squeeze(data(pi,si,mi,ri,:))')]; %#ok<AGROW>
            end
        end
    end
end
raw = cell2table(rawRows, 'VariableNames', [{'Profile','Scenario','Algorithm','RunIndex'}, metricFields]);
writetable(summary, results_file('csv', 'reproduction_gap_summary.csv'));
writetable(raw, results_file('csv', 'reproduction_gap_raw.csv'));
save(results_file('mat', 'reproduction_gap.mat'), 'data', 'summary', 'raw', 'methods', 'scenarios', 'profiles', 'metricFields', 'nRuns');
fprintf('Saved V2 results under %s\n', results_paths().root);
