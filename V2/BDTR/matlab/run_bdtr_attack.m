function run_bdtr_attack()
% RUN_BDTR_ATTACK  Execute BDTR on the Attack dataset (9 configs x 30 seeds x 2 scenarios = 540 runs).
%
% Reads only from shared/config/ and shared/datasets/.
% Verifies pairing across seeds 1..30 and asserts three-way outcome conservation per run.
% Writes per-run CSV to results/BDTR/attack/bdtr_attack_runs.csv.

bdtrDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(bdtrDir));
addpath(fullfile(rootDir, 'shared', 'config'));
addpath(bdtrDir);

w1 = warning('off', 'MATLAB:dispatcher:nameConflict');
w2 = warning('off', 'MATLAB:mpath:nameNonexistentOrNotADirectory');
cleanupWarn = onCleanup(@() restoreWarnings(w1, w2));

cfgExp = experiment_config();

% ---- Assert config invariants ----
assert(all(cfgExp.attack.strengths > 0 & cfgExp.attack.strengths < 1), ...
    'run_bdtr_attack:badStrength', 'Strengths must be fractions in (0, 1).');
assert(isempty(intersect(cfgExp.attack.seeds, cfgExp.montecarlo.seeds)), ...
    'run_bdtr_attack:seedOverlap', 'Attack and Monte Carlo seeds overlap.');

dsDir  = cfgExp.paths.datasetsDir;
outDir = fullfile(cfgExp.paths.resultsRoot, 'BDTR', 'attack');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

nSc       = numel(cfgExp.scenarios.names);
nStrat    = numel(cfgExp.strategies);
nStr      = numel(cfgExp.attack.strengths);
nReps     = cfgExp.attack.nReps;
totalRuns = nSc * nStrat * nStr * nReps;

rows   = cell(totalRuns, 24);
rowIdx = 0;

fprintf('====================================================================================\n');
fprintf('  BDTR ATTACK EXPERIMENT: %d RUNS (%d scenarios x %d configs x %d seeds)\n', ...
    totalRuns, nSc, nStrat * nStr, nReps);
fprintf('====================================================================================\n');
tic;

for scIdx = 1:nSc
    scName  = cfgExp.scenarios.names{scIdx};
    matPath = fullfile(dsDir, sprintf('attack_%s.mat', scName));
    assert(exist(matPath, 'file') == 2, 'Missing dataset: %s', matPath);

    loaded = load(matPath, 'runs', 'meta');
    runs   = loaded.runs;
    assert(isequal(size(runs), [nReps, nStrat, nStr]), 'Unexpected runs dimensions in %s.', matPath);

    verifyAttackPairing(runs, scName, cfgExp.attack.seeds);
    fprintf('[PASS] Pre-run pairing check verified for %s (%d seeds x 9 configs).\n', scName, nReps);

    clear sim;
    for sIdx = 1:nStrat
        for kIdx = 1:nStr
            for rIdx = 1:nReps
                item = runs(rIdx, sIdx, kIdx);
                assert(item.strength > 0 && item.strength < 1, 'Strength must be in (0, 1).');
                assert(ismember(item.seed, cfgExp.attack.seeds), 'Unexpected seed %d.', item.seed);
                assert(item.cfg.sim.includeTravel == true, 'Expected includeTravel == true.');

                res = sim(item.cfg, 'bdtr');
                m   = res.metrics;

                nT = numel(res.tasks);
                unfinishedRate = sum(~strcmp({res.tasks.status}, 'complete') & ...
                                     ~strcmp({res.tasks.status}, 'failed')) / nT;
                assert(abs(m.completionRate + m.failedRate + unfinishedRate - 1) < 1e-9, ...
                    'run_bdtr_attack:outcomeSum', ...
                    'Outcome conservation failed on %s/%s/%.2f seed %d.', ...
                    scName, item.strategyCode, item.strength, item.seed);

                rowIdx = rowIdx + 1;
                rows(rowIdx, :) = { ...
                    "BDTR", string(item.scenario), "attack", ...
                    string(item.strategyLabel), string(item.strategyCode), ...
                    item.strength, item.realisedSlots, item.runIndex, ...
                    item.seed, item.instanceSeed, item.attackSeed, ...
                    cfgExp.attack.timingWindow(1), cfgExp.attack.timingWindow(2), ...
                    m.feasibilityRate, m.completionRate, m.failedRate, unfinishedRate, ...
                    m.reallocationCount, m.preemptionCount, m.meanCompletionTime, ...
                    m.R_task, m.R_time, m.CRI, m.throughputRecovery ...
                };
            end
        end
        fprintf('  [%s | %-8s] completed %d/%d runs (%.1fs elapsed)\n', scName, cfgExp.strategies(sIdx).label, rowIdx, totalRuns, toc);
    end
end

varNames = {'algorithm', 'scenario', 'experiment', 'strategy_label', 'strategy_code', ...
    'strength', 'realised_slots', 'run_index', 'seed', 'instance_seed', 'attack_seed', ...
    'timing_window_min', 'timing_window_max', ...
    'feasibilityRate', 'completionRate', 'failedRate', 'unfinishedRate', ...
    'reallocationCount', 'preemptionCount', 'meanCompletionTime', ...
    'R_task', 'R_time', 'CRI', 'throughputRecovery'};

resultsTable = cell2table(rows, 'VariableNames', varNames);
csvPath = fullfile(outDir, 'bdtr_attack_runs.csv');
writetable(resultsTable, csvPath);
fprintf('Saved %d rows to %s\n\n', height(resultsTable), csvPath);
end

function verifyAttackPairing(runs, scName, expectedSeeds)
    [nReps, nStrat, nStr] = size(runs);
    checkFields = {'uav', 'task', 'capabilities', 'bdtr', 'sim', 'cost'};
    for rIdx = 1:nReps
        refCfg  = runs(rIdx, 1, 1).cfg;
        refSeed = runs(rIdx, 1, 1).seed;
        assert(refSeed == expectedSeeds(rIdx), 'Unexpected seed order at row %d.', rIdx);
        for sIdx = 1:nStrat
            for kIdx = 1:nStr
                candCfg = runs(rIdx, sIdx, kIdx).cfg;
                assert(runs(rIdx, sIdx, kIdx).seed == refSeed, 'Seed mismatch in pairing check.');
                for f = 1:numel(checkFields)
                    fn = checkFields{f};
                    if ~isequaln(candCfg.(fn), refCfg.(fn))
                        error('run_bdtr_attack:pairingFailed', ...
                            'Pairing check failed in %s at seed %d (strategy %d, strength %d): field "%s" differs.', ...
                            scName, refSeed, sIdx, kIdx, fn);
                    end
                end
            end
        end
    end
end

function restoreWarnings(w1, w2)
    warning(w1);
    warning(w2);
end
