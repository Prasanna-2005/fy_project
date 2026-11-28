function generate_datasets()
% GENERATE_DATASETS  Generate read-only benchmark datasets into shared/datasets/.
%
% Sole writer to shared/datasets/. Refuses to overwrite existing datasets.
% Sets explicit rng(seed, 'twister') before every instance and attack draw,
% and verifies seeds 1..30 pairing across all 9 attack configurations.

genDir    = fileparts(mfilename('fullpath'));
sharedDir = fileparts(genDir);
configDir = fullfile(sharedDir, 'config');
addpath(configDir);
addpath(genDir);

cfgExp = experiment_config();

% ---- Validate shared config invariants ----
assert(all(cfgExp.attack.strengths > 0 & cfgExp.attack.strengths < 1), ...
    'generate_datasets:badAttackStrength', 'Attack strengths must be fractions in (0, 1).');
assert(cfgExp.montecarlo.strength > 0 && cfgExp.montecarlo.strength < 1, ...
    'generate_datasets:badMCStrength', 'Monte Carlo strength must be a fraction in (0, 1).');
assert(isempty(intersect(cfgExp.attack.seeds, cfgExp.montecarlo.seeds)), ...
    'generate_datasets:seedOverlap', 'Attack seeds and Monte Carlo seeds must not overlap.');
assert(numel(cfgExp.attack.seeds) == cfgExp.attack.nReps, ...
    'generate_datasets:badAttackSeedCount', 'Attack seed count must equal nReps.');
assert(numel(cfgExp.montecarlo.seeds) == cfgExp.montecarlo.nRuns, ...
    'generate_datasets:badMCSeedCount', 'MC seed count must equal nRuns.');

% ---- Refuse to overwrite existing datasets ----
dsDir = cfgExp.paths.datasetsDir;
if ~exist(dsDir, 'dir')
    mkdir(dsDir);
end

targetFiles = { ...
    fullfile(dsDir, 'attack_small.mat'), ...
    fullfile(dsDir, 'attack_large.mat'), ...
    fullfile(dsDir, 'mc_small.mat'), ...
    fullfile(dsDir, 'mc_large.mat') ...
};
for i = 1:numel(targetFiles)
    if exist(targetFiles{i}, 'file')
        error('generate_datasets:alreadyExists', ...
            'Refusing to overwrite existing dataset file: %s', targetFiles{i});
    end
end

rngAlg = cfgExp.seeding.rngAlgorithm;

fprintf('====================================================================================\n');
fprintf('  GENERATING READ-ONLY DATASETS (travel: 5 m/s, window: [%.2f, %.2f])\n', ...
    cfgExp.attack.timingWindow(1), cfgExp.attack.timingWindow(2));
fprintf('====================================================================================\n');

% ---- Generate Attack Datasets (3 strategies x 3 strengths x 30 seeds per scenario) ----
nStrat = numel(cfgExp.strategies);
nStr   = numel(cfgExp.attack.strengths);
nReps  = cfgExp.attack.nReps;

for scIdx = 1:numel(cfgExp.scenarios.names)
    scName = cfgExp.scenarios.names{scIdx};
    scDef  = cfgExp.scenarios.(scName);

    runs = repmat(struct( ...
        'scenario',      scName, ...
        'experiment',    'attack', ...
        'runIndex',      0, ...
        'seed',          0, ...
        'instanceSeed',  0, ...
        'attackSeed',    0, ...
        'strategyLabel', '', ...
        'strategyCode',  '', ...
        'strength',      0, ...
        'realisedSlots', 0, ...
        'cfg',           struct()), nReps, nStrat, nStr);

    for rIdx = 1:nReps
        seed     = cfgExp.attack.seeds(rIdx);
        instSeed = seed + cfgExp.seeding.instanceSeedOffset;
        atkSeed  = seed + cfgExp.seeding.attackSeedOffset;

        for sIdx = 1:nStrat
            sLabel = cfgExp.strategies(sIdx).label;
            sCode  = cfgExp.strategies(sIdx).code;

            for kIdx = 1:nStr
                strVal      = cfgExp.attack.strengths(kIdx);
                expectSlots = cfgExp.attack.realisedSlots.(scName)(kIdx);

                rng(instSeed, rngAlg);
                baseCfg = common_config('bdtr', scName, instSeed);
                assert(baseCfg.sim.includeTravel == true, 'Expected includeTravel == true.');
                assert(all(isfinite([baseCfg.task.deadline])), 'Expected finite deadlines.');

                rng(atkSeed, rngAlg);
                ev = generate_attack_events(baseCfg, strVal, sCode, atkSeed, cfgExp.attack.timingWindow);
                assert(numel(ev) == expectSlots, ...
                    'Slot count mismatch for %s/%s/%.2f seed %d: got %d, expected %d.', ...
                    scName, sCode, strVal, seed, numel(ev), expectSlots);

                baseCfg.capabilityChanges = ev;

                runs(rIdx, sIdx, kIdx).scenario      = scName;
                runs(rIdx, sIdx, kIdx).experiment    = 'attack';
                runs(rIdx, sIdx, kIdx).runIndex      = rIdx;
                runs(rIdx, sIdx, kIdx).seed          = seed;
                runs(rIdx, sIdx, kIdx).instanceSeed  = instSeed;
                runs(rIdx, sIdx, kIdx).attackSeed    = atkSeed;
                runs(rIdx, sIdx, kIdx).strategyLabel = sLabel;
                runs(rIdx, sIdx, kIdx).strategyCode  = sCode;
                runs(rIdx, sIdx, kIdx).strength      = strVal;
                runs(rIdx, sIdx, kIdx).realisedSlots = numel(ev);
                runs(rIdx, sIdx, kIdx).cfg           = baseCfg;
            end
        end
    end

    verifyAttackPairing(runs, scName);
    fprintf('[PASS] Pairing check verified for attack_%s (30 seeds x 9 configs = %d runs).\n', scName, numel(runs));

    meta = struct('scenario', scName, 'scenarioDef', scDef, 'experiment', 'attack', ...
        'timingWindow', cfgExp.attack.timingWindow, 'seeds', cfgExp.attack.seeds);

    outMat = fullfile(dsDir, sprintf('attack_%s.mat', scName));
    save(outMat, 'runs', 'meta');
    fprintf('  Wrote %s\n', outMat);
end

% ---- Generate Monte Carlo Datasets (Random, 0.55, 300 seeds per scenario) ----
nMC          = cfgExp.montecarlo.nRuns;
mcStratLabel = cfgExp.montecarlo.strategyLabel;
mcStratCode  = cfgExp.montecarlo.strategyCode;
mcStrength   = cfgExp.montecarlo.strength;
mcWindow     = cfgExp.montecarlo.timingWindow;

for scIdx = 1:numel(cfgExp.scenarios.names)
    scName      = cfgExp.scenarios.names{scIdx};
    scDef       = cfgExp.scenarios.(scName);
    expectSlots = cfgExp.montecarlo.realisedSlots.(scName);

    runs = repmat(struct( ...
        'scenario',      scName, ...
        'experiment',    'montecarlo', ...
        'runIndex',      0, ...
        'seed',          0, ...
        'instanceSeed',  0, ...
        'attackSeed',    0, ...
        'strategyLabel', mcStratLabel, ...
        'strategyCode',  mcStratCode, ...
        'strength',      mcStrength, ...
        'realisedSlots', expectSlots, ...
        'cfg',           struct()), nMC, 1);

    for rIdx = 1:nMC
        seed     = cfgExp.montecarlo.seeds(rIdx);
        instSeed = seed + cfgExp.seeding.instanceSeedOffset;
        atkSeed  = seed + cfgExp.seeding.attackSeedOffset;

        rng(instSeed, rngAlg);
        baseCfg = common_config('bdtr', scName, instSeed);
        assert(baseCfg.sim.includeTravel == true, 'Expected includeTravel == true.');
        assert(all(isfinite([baseCfg.task.deadline])), 'Expected finite deadlines.');

        rng(atkSeed, rngAlg);
        ev = generate_attack_events(baseCfg, mcStrength, mcStratCode, atkSeed, mcWindow);
        assert(numel(ev) == expectSlots, ...
            'MC slot mismatch for %s seed %d: got %d, expected %d.', scName, seed, numel(ev), expectSlots);

        baseCfg.capabilityChanges = ev;

        runs(rIdx).scenario      = scName;
        runs(rIdx).experiment    = 'montecarlo';
        runs(rIdx).runIndex      = rIdx;
        runs(rIdx).seed          = seed;
        runs(rIdx).instanceSeed  = instSeed;
        runs(rIdx).attackSeed    = atkSeed;
        runs(rIdx).strategyLabel = mcStratLabel;
        runs(rIdx).strategyCode  = mcStratCode;
        runs(rIdx).strength      = mcStrength;
        runs(rIdx).realisedSlots = numel(ev);
        runs(rIdx).cfg           = baseCfg;
    end

    meta = struct('scenario', scName, 'scenarioDef', scDef, 'experiment', 'montecarlo', ...
        'strategyLabel', mcStratLabel, 'strategyCode', mcStratCode, ...
        'strength', mcStrength, 'realisedSlots', expectSlots, ...
        'timingWindow', mcWindow, 'seeds', cfgExp.montecarlo.seeds);

    outMat = fullfile(dsDir, sprintf('mc_%s.mat', scName));
    save(outMat, 'runs', 'meta');
    fprintf('  Wrote %s\n', outMat);
end

fprintf('\nAll datasets generated successfully.\n');
end

function verifyAttackPairing(runs, scName)
    [nReps, nStrat, nStr] = size(runs);
    checkFields = {'uav', 'task', 'capabilities', 'bdtr', 'sim', 'cost'};
    for rIdx = 1:nReps
        refCfg  = runs(rIdx, 1, 1).cfg;
        refSeed = runs(rIdx, 1, 1).seed;
        for sIdx = 1:nStrat
            for kIdx = 1:nStr
                candCfg = runs(rIdx, sIdx, kIdx).cfg;
                if candCfg.sim.tEnd ~= refCfg.sim.tEnd || candCfg.sim.dt ~= refCfg.sim.dt
                    error('generate_datasets:pairingFailed', ...
                        'Pairing failed in %s seed %d config (%d,%d): sim field mismatch.', scName, refSeed, sIdx, kIdx);
                end
                for f = 1:numel(checkFields)
                    fn = checkFields{f};
                    if ~isequaln(candCfg.(fn), refCfg.(fn))
                        error('generate_datasets:pairingFailed', ...
                            'Pairing check failed in %s at seed %d (strategy %d, strength %d): field "%s" differs.', ...
                            scName, refSeed, sIdx, kIdx, fn);
                    end
                end
            end
        end
    end
end
