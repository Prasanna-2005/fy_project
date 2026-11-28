function run_bdtr_mc()
% RUN_BDTR_MC  Execute BDTR on the Monte Carlo dataset (300 seeds x 2 scenarios = 600 runs).
%
% Strategy fixed at Random ('random'), interruption strength fixed at 0.55.
% Reads only from shared/config/ and shared/datasets/.
% Asserts fixed conditions and three-way outcome conservation per run.
% Writes per-run CSV to results/BDTR/montecarlo/bdtr_mc_runs.csv.

bdtrDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(bdtrDir));
addpath(fullfile(rootDir, 'shared', 'config'));
addpath(bdtrDir);

w1 = warning('off', 'MATLAB:dispatcher:nameConflict');
w2 = warning('off', 'MATLAB:mpath:nameNonexistentOrNotADirectory');
cleanupWarn = onCleanup(@() restoreWarnings(w1, w2));

cfgExp = experiment_config();

% ---- Assert config invariants ----
assert(cfgExp.montecarlo.strength > 0 && cfgExp.montecarlo.strength < 1, ...
    'run_bdtr_mc:badStrength', 'MC strength must be a fraction in (0, 1).');
assert(isempty(intersect(cfgExp.attack.seeds, cfgExp.montecarlo.seeds)), ...
    'run_bdtr_mc:seedOverlap', 'Attack and Monte Carlo seeds overlap.');

dsDir  = cfgExp.paths.datasetsDir;
outDir = fullfile(cfgExp.paths.resultsRoot, 'BDTR', 'montecarlo');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

nSc       = numel(cfgExp.scenarios.names);
nRuns     = cfgExp.montecarlo.nRuns;
totalRuns = nSc * nRuns;

rows   = cell(totalRuns, 24);
rowIdx = 0;

fprintf('====================================================================================\n');
fprintf('  BDTR MONTE CARLO EXPERIMENT: %d RUNS (%d scenarios x %d seeds; %s, I=%.2f)\n', ...
    totalRuns, nSc, nRuns, cfgExp.montecarlo.strategyLabel, cfgExp.montecarlo.strength);
fprintf('====================================================================================\n');
tic;

for scIdx = 1:nSc
    scName  = cfgExp.scenarios.names{scIdx};
    matPath = fullfile(dsDir, sprintf('mc_%s.mat', scName));
    assert(exist(matPath, 'file') == 2, 'Missing dataset: %s', matPath);

    loaded = load(matPath, 'runs', 'meta');
    runs   = loaded.runs;
    assert(numel(runs) == nRuns, 'Unexpected MC run count in %s.', matPath);

    expectSlots = cfgExp.montecarlo.realisedSlots.(scName);

    clear sim;
    for rIdx = 1:nRuns
        item = runs(rIdx);
        assert(strcmp(item.strategyCode, cfgExp.montecarlo.strategyCode), 'MC strategyCode mismatch.');
        assert(strcmp(item.strategyLabel, cfgExp.montecarlo.strategyLabel), 'MC strategyLabel mismatch.');
        assert(abs(item.strength - cfgExp.montecarlo.strength) < 1e-12, 'MC strength mismatch.');
        assert(item.realisedSlots == expectSlots, 'MC realisedSlots mismatch.');
        assert(item.seed == cfgExp.montecarlo.seeds(rIdx), 'MC seed mismatch.');
        assert(item.cfg.sim.includeTravel == true, 'Expected includeTravel == true.');

        res = sim(item.cfg, 'bdtr');
        m   = res.metrics;

        nT = numel(res.tasks);
        unfinishedRate = sum(~strcmp({res.tasks.status}, 'complete') & ...
                             ~strcmp({res.tasks.status}, 'failed')) / nT;
        assert(abs(m.completionRate + m.failedRate + unfinishedRate - 1) < 1e-9, ...
            'run_bdtr_mc:outcomeSum', 'Outcome conservation failed on %s seed %d.', scName, item.seed);

        rowIdx = rowIdx + 1;
        rows(rowIdx, :) = { ...
            "BDTR", string(item.scenario), "montecarlo", ...
            string(item.strategyLabel), string(item.strategyCode), ...
            item.strength, item.realisedSlots, item.runIndex, ...
            item.seed, item.instanceSeed, item.attackSeed, ...
            cfgExp.montecarlo.timingWindow(1), cfgExp.montecarlo.timingWindow(2), ...
            m.feasibilityRate, m.completionRate, m.failedRate, unfinishedRate, ...
            m.reallocationCount, m.preemptionCount, m.meanCompletionTime, ...
            m.R_task, m.R_time, m.CRI, m.throughputRecovery ...
        };

        if mod(rIdx, 100) == 0
            fprintf('  [%s] completed %3d/%d (total %3d/%d, %.1fs elapsed)\n', ...
                scName, rIdx, nRuns, rowIdx, totalRuns, toc);
        end
    end
end

varNames = {'algorithm', 'scenario', 'experiment', 'strategy_label', 'strategy_code', ...
    'strength', 'realised_slots', 'run_index', 'seed', 'instance_seed', 'attack_seed', ...
    'timing_window_min', 'timing_window_max', ...
    'feasibilityRate', 'completionRate', 'failedRate', 'unfinishedRate', ...
    'reallocationCount', 'preemptionCount', 'meanCompletionTime', ...
    'R_task', 'R_time', 'CRI', 'throughputRecovery'};

resultsTable = cell2table(rows, 'VariableNames', varNames);
csvPath = fullfile(outDir, 'bdtr_mc_runs.csv');
writetable(resultsTable, csvPath);
fprintf('Saved %d rows to %s\n\n', height(resultsTable), csvPath);
end

function restoreWarnings(w1, w2)
    warning(w1);
    warning(w2);
end
