function plot_results(algoName, experimentFilter)
% PLOT_RESULTS  Algorithm-agnostic plot generator for benchmark outputs.
%
% Usage:
%   plot_results("BDTR")               % generates Figures 1-4 from results/BDTR/
%   plot_results("BDTR", "attack")     % optional: only attack figures (Fig 1 & Fig 4)
%   plot_results("BDTR", "montecarlo") % optional: only Monte Carlo figures (Fig 2 & Fig 3)
%
% Reads only shared/config/experiment_config.m and results/<ALGO>/.
% Never reruns any simulation. Writes 300 dpi PNG files to plots/<ALGO>/.

if nargin < 1 || isempty(algoName)
    error('plot_results:missingAlgo', 'Algorithm name is required, e.g., plot_results("BDTR").');
end
if nargin < 2 || isempty(experimentFilter)
    experimentFilter = "all";
end

algoStr = char(string(algoName));
expMode = lower(string(experimentFilter));
if ~ismember(expMode, ["all", "attack", "montecarlo"])
    error('plot_results:badFilter', 'experimentFilter must be "all", "attack", or "montecarlo".');
end

plotDir   = fileparts(mfilename('fullpath'));
sharedDir = fileparts(plotDir);
addpath(fullfile(sharedDir, 'config'));
cfgExp    = experiment_config();

algoResultsDir = fullfile(cfgExp.paths.resultsRoot, algoStr);
if ~exist(algoResultsDir, 'dir')
    error('plot_results:missingAlgoResults', ...
        'Results directory does not exist for algorithm "%s": %s', algoStr, algoResultsDir);
end

needAttack = (expMode == "all") || (expMode == "attack");
needMC     = (expMode == "all") || (expMode == "montecarlo");

atkTable    = table();
mcTable     = table();
missingList = {};

if needAttack
    atkDir = fullfile(algoResultsDir, 'attack');
    atkCsv = locateExperimentCsv(atkDir, 'attack');
    if isempty(atkCsv)
        missingList{end+1} = fullfile(atkDir, '*_attack_runs.csv'); %#ok<AGROW>
    else
        atkTable = readtable(atkCsv, 'TextType', 'string');
        validateAttackTable(atkTable, cfgExp, atkCsv);
    end
end

if needMC
    mcDir = fullfile(algoResultsDir, 'montecarlo');
    mcCsv = locateExperimentCsv(mcDir, 'montecarlo');
    if isempty(mcCsv)
        missingList{end+1} = fullfile(mcDir, '*_mc_runs.csv'); %#ok<AGROW>
    else
        mcTable = readtable(mcCsv, 'TextType', 'string');
        validateMCTable(mcTable, cfgExp, mcCsv);
    end
end

if ~isempty(missingList)
    error('plot_results:incompleteResults', ...
        'Missing required results for "%s": %s', algoStr, strjoin(missingList, '; '));
end

outPlotDir = fullfile(cfgExp.paths.plotsRoot, algoStr);
if ~exist(outPlotDir, 'dir')
    mkdir(outPlotDir);
end

writtenFiles = {};

if needAttack
    f1 = plotFig1AttackHeatmap(atkTable, cfgExp, algoStr, outPlotDir);
    writtenFiles = [writtenFiles, f1]; %#ok<AGROW>
end

if needMC
    f2 = plotFig2MCDistributions(mcTable, cfgExp, algoStr, outPlotDir);
    f3 = plotFig3MCMetrics(mcTable, cfgExp, outPlotDir);
    writtenFiles = [writtenFiles, f2, f3]; %#ok<AGROW>
end

if needAttack
    f4 = plotFig4CriVsAttack(atkTable, cfgExp, outPlotDir);
    writtenFiles = [writtenFiles, f4]; %#ok<AGROW>
end

fprintf('\n====================================================================================\n');
fprintf('  PLOT_RESULTS SUMMARY (%s | mode: %s | colormap: %s)\n', algoStr, expMode, cfgExp.plotting.colormap);
fprintf('====================================================================================\n');
fprintf('Written files (%d):\n', numel(writtenFiles));
for i = 1:numel(writtenFiles)
    fprintf('  - %s\n', writtenFiles{i});
end
fprintf('Missing results: none\n\n');
end

%% ======================= INPUT LOCATORS & VALIDATORS =======================

function csvPath = locateExperimentCsv(expDir, expKind)
    csvPath = '';
    if ~exist(expDir, 'dir')
        return;
    end
    if strcmp(expKind, 'attack')
        csvMatches = dir(fullfile(expDir, '*attack*.csv'));
    else
        csvMatches = dir(fullfile(expDir, '*mc*.csv'));
    end
    if isempty(csvMatches)
        csvMatches = dir(fullfile(expDir, '*.csv'));
    end
    if ~isempty(csvMatches)
        csvPath = fullfile(expDir, csvMatches(1).name);
    end
end

function validateAttackTable(T, cfgExp, csvPath)
    reqCols = {'scenario', 'strategy_label', 'strategy_code', 'strength', 'seed', ...
               cfgExp.metrics.primary, 'CRI'};
    for i = 1:numel(reqCols)
        if ~ismember(reqCols{i}, T.Properties.VariableNames)
            error('plot_results:missingColumn', 'Column "%s" missing in %s.', reqCols{i}, csvPath);
        end
    end
    expectedRows = numel(cfgExp.scenarios.names) * numel(cfgExp.strategies) * ...
                   numel(cfgExp.attack.strengths) * cfgExp.attack.nReps;
    if height(T) ~= expectedRows
        error('plot_results:incompleteAttackRows', ...
            'Expected %d rows in %s, found %d.', expectedRows, csvPath, height(T));
    end
end

function validateMCTable(T, cfgExp, csvPath)
    reqCols = [{'scenario', 'strategy_code', 'strength', 'seed', cfgExp.metrics.primary}, ...
               cfgExp.plotting.mcSummary.metrics];
    for i = 1:numel(reqCols)
        if ~ismember(reqCols{i}, T.Properties.VariableNames)
            error('plot_results:missingColumn', 'Column "%s" missing in %s.', reqCols{i}, csvPath);
        end
    end
    expectedRows = numel(cfgExp.scenarios.names) * cfgExp.montecarlo.nRuns;
    if height(T) ~= expectedRows
        error('plot_results:incompleteMCRows', ...
            'Expected %d rows in %s, found %d.', expectedRows, csvPath, height(T));
    end
end

%% ======================= FIGURE 1: ATTACK HEATMAP =======================

function files = plotFig1AttackHeatmap(T, cfgExp, algoStr, outDir)
    metricName  = cfgExp.metrics.primary;
    stratLabels = {cfgExp.strategies.label};
    stratCodes  = {cfgExp.strategies.code};
    strengths   = cfgExp.attack.strengths;
    scenarios   = cfgExp.scenarios.names;

    nR = numel(stratCodes);
    nC = numel(strengths);
    meanMats = cell(1, numel(scenarios));
    stdMats  = cell(1, numel(scenarios));

    globalMin = inf;
    globalMax = -inf;

    for si = 1:numel(scenarios)
        sc = scenarios{si};
        M = zeros(nR, nC);
        S = zeros(nR, nC);
        for ri = 1:nR
            for ci = 1:nC
                mask = strcmpi(T.scenario, sc) & ...
                       strcmpi(T.strategy_code, stratCodes{ri}) & ...
                       abs(T.strength - strengths(ci)) < 1e-9;
                vals = T.(metricName)(mask) * 100;
                if numel(vals) ~= cfgExp.attack.nReps
                    error('plot_results:missingAttackCell', ...
                        'Expected %d runs for %s/%s/%.2f, got %d.', ...
                        cfgExp.attack.nReps, sc, stratCodes{ri}, strengths(ci), numel(vals));
                end
                M(ri, ci) = mean(vals);
                S(ri, ci) = std(vals);
            end
        end
        meanMats{si} = M;
        stdMats{si}  = S;
        globalMin = min(globalMin, min(M(:)));
        globalMax = max(globalMax, max(M(:)));
    end

    cLow  = max(0, floor(globalMin - 1));
    cHigh = min(100, ceil(globalMax + 1));
    if cHigh <= cLow
        cLow = 0; cHigh = 100;
    end

    cmap = feval(cfgExp.plotting.colormap, 256);

    hFig = figure('Name', 'Figure 1: Attack Matrix Heatmap', 'Color', 'w', ...
        'Visible', 'off', 'Position', [80, 80, 1280, 520]);
    try hFig.Theme = 'light'; catch, end
    colormap(hFig, cmap);

    tl = tiledlayout(hFig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
    title(tl, sprintf('%s — Task Completion Rate Across Attack Strategies & Strengths', algoStr), ...
        'FontSize', 14, 'FontWeight', 'bold', 'Color', [0 0 0], 'Interpreter', 'none');
    subtitle(tl, sprintf('n = %d paired seeds per cell | Travel: 5 m/s | Deadlines: finite | Window: [%.2f, %.2f] | Colormap: %s', ...
        cfgExp.attack.nReps, cfgExp.attack.timingWindow(1), cfgExp.attack.timingWindow(2), cfgExp.plotting.colormap), ...
        'FontSize', 10, 'Color', [0.20 0.20 0.20], 'Interpreter', 'none');

    for si = 1:numel(scenarios)
        sc    = scenarios{si};
        scDef = cfgExp.scenarios.(sc);
        slots = cfgExp.attack.realisedSlots.(sc);

        ax = nexttile(tl, si);
        M  = meanMats{si};
        S  = stdMats{si};
        imagesc(ax, M, [cLow, cHigh]);
        hold(ax, 'on');

        for xg = 0.5:1:(nC + 0.5)
            plot(ax, [xg xg], [0.5, nR + 0.5], 'Color', [1 1 1], 'LineWidth', 1.2);
        end
        for yg = 0.5:1:(nR + 0.5)
            plot(ax, [0.5, nC + 0.5], [yg yg], 'Color', [1 1 1], 'LineWidth', 1.2);
        end

        xLabels = cell(1, nC);
        for ci = 1:nC
            xLabels{ci} = sprintf('%.2f (%d/%d)', strengths(ci), slots(ci), scDef.totalSlots);
        end

        set(ax, 'XTick', 1:nC, 'XTickLabel', xLabels, ...
            'YTick', 1:nR, 'YTickLabel', stratLabels, ...
            'FontSize', 10.5, 'FontWeight', 'bold', 'TickLength', [0 0]);
        xlabel(ax, 'Interruption Strength (fraction & realised slots)', 'FontWeight', 'bold');
        if si == 1
            ylabel(ax, 'Attack Strategy', 'FontWeight', 'bold');
        end
        title(ax, sprintf('%s (%d UAVs, %d tasks)', scDef.label, scDef.nUAV, scDef.nTasks), ...
            'FontSize', 12, 'FontWeight', 'bold', 'Color', [0 0 0]);

        for ri = 1:nR
            for ci = 1:nC
                normVal = (M(ri, ci) - cLow) / max(1e-9, cHigh - cLow);
                cIdx = max(1, min(size(cmap, 1), round(normVal * (size(cmap, 1) - 1)) + 1));
                rgb  = cmap(cIdx, :);
                lum  = 0.2126 * rgb(1) + 0.7152 * rgb(2) + 0.0722 * rgb(3);
                if lum < 0.52
                    txtCol = [1 1 1];
                else
                    txtCol = [0 0 0];
                end
                text(ax, ci, ri, sprintf('%.2f%%\n± %.2f%%', M(ri, ci), S(ri, ci)), ...
                    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                    'FontSize', 10.5, 'FontWeight', 'bold', 'Color', txtCol);
            end
        end
        styleCleanAxes(ax);
    end

    cb = colorbar(ax);
    cb.Layout.Tile = 'east';
    cb.Color = [0 0 0];
    cb.Label.String = 'Completion Rate (%)';
    cb.Label.FontSize = 11;
    cb.Label.FontWeight = 'bold';
    cb.Label.Color = [0 0 0];

    files = saveFigurePng(hFig, outDir, 'fig1_attack_heatmap', cfgExp.plotting.dpi);
end

%% ======================= FIGURE 2: MC DISTRIBUTIONS =======================

function files = plotFig2MCDistributions(T, cfgExp, algoStr, outDir)
    metricName = cfgExp.metrics.primary;
    scenarios  = cfgExp.scenarios.names;

    valsCell = cell(1, numel(scenarios));
    allVals  = [];
    for si = 1:numel(scenarios)
        mask = strcmpi(T.scenario, scenarios{si});
        v = T.(metricName)(mask) * 100;
        valsCell{si} = v;
        allVals = [allVals; v(:)]; %#ok<AGROW>
    end

    xMin  = max(0, floor(min(allVals) - 2));
    xMax  = min(100, ceil(max(allVals) + 2));
    edges = linspace(xMin, xMax, 25);

    hFig = figure('Name', 'Figure 2: Monte Carlo Distributions', 'Color', 'w', ...
        'Visible', 'off', 'Position', [80, 80, 1240, 500]);
    try hFig.Theme = 'light'; catch, end
    tl = tiledlayout(hFig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
    title(tl, sprintf('%s — Monte Carlo Completion Rate Distributions (%s, I = %.2f)', ...
        algoStr, cfgExp.montecarlo.strategyLabel, cfgExp.montecarlo.strength), ...
        'FontSize', 14, 'FontWeight', 'bold', 'Color', [0 0 0]);

    colors   = {[0.18, 0.48, 0.72], [0.82, 0.36, 0.18]};
    maxY     = 0;
    axesList = gobjects(1, numel(scenarios));

    for si = 1:numel(scenarios)
        sc    = scenarios{si};
        scDef = cfgExp.scenarios.(sc);
        v  = valsCell{si};
        mu = mean(v);
        sd = std(v);
        n  = numel(v);

        ax = nexttile(tl, si);
        axesList(si) = ax;
        hold(ax, 'on');

        h = histogram(ax, v, edges, 'FaceColor', colors{si}, 'EdgeColor', 'w', 'FaceAlpha', 0.80, ...
            'DisplayName', sprintf('n = %d runs', n));
        yTop = max(h.Values) * 1.18;
        maxY = max(maxY, yTop);

        bandLo = max(xMin, mu - sd);
        bandHi = min(xMax, mu + sd);
        p = patch(ax, [bandLo, bandHi, bandHi, bandLo], [0, 0, yTop, yTop], colors{si}, ...
            'FaceAlpha', 0.14, 'EdgeColor', 'none', ...
            'DisplayName', sprintf('±1 SD (%.2f%%)', sd));
        uistack(p, 'bottom');

        xline(ax, mu, 'k--', 'LineWidth', 2.0, ...
            'DisplayName', sprintf('Mean = %.2f%%', mu));

        xlim(ax, [xMin, xMax]);
        xlabel(ax, 'Completion Rate (%)', 'FontWeight', 'bold');
        ylabel(ax, 'Run Count', 'FontWeight', 'bold');
        title(ax, sprintf('%s (%d/%d slots degraded)', scDef.label, ...
            cfgExp.montecarlo.realisedSlots.(sc), scDef.totalSlots), ...
            'FontSize', 12, 'FontWeight', 'bold', 'Color', [0 0 0]);
        lg = legend(ax, 'Location', 'northwest', 'Box', 'on', 'FontSize', 9.5);
        lg.Color = [1 1 1]; lg.TextColor = [0 0 0]; lg.EdgeColor = [0.6 0.6 0.6];
        grid(ax, 'on');
        styleCleanAxes(ax);
    end

    for si = 1:numel(scenarios)
        ylim(axesList(si), [0, max(10, ceil(maxY))]);
        patches = findobj(axesList(si), 'Type', 'Patch');
        for pIdx = 1:numel(patches)
            yd = patches(pIdx).YData;
            yd(yd > 0) = max(10, ceil(maxY));
            patches(pIdx).YData = yd;
        end
    end

    files = saveFigurePng(hFig, outDir, 'fig2_mc_distributions', cfgExp.plotting.dpi);
end

%% ======================= FIGURE 3: MONTE CARLO METRICS SUMMARY =======================

function files = plotFig3MCMetrics(T, cfgExp, outDir)
    ms        = cfgExp.plotting.mcSummary;
    metrics   = ms.metrics;
    zVal      = ms.zValue;
    yBounds   = ms.yLim;
    scenarios = cfgExp.scenarios.names;
    nM        = numel(metrics);
    nSc       = numel(scenarios);
    nExpected = cfgExp.montecarlo.nRuns;

    means = zeros(nM, nSc);
    cis   = zeros(nM, nSc);
    stds  = zeros(nM, nSc);

    fprintf('\n--- Figure 3: Monte Carlo summary (%s, strength %.2f, n = %d) ---\n', ...
        cfgExp.montecarlo.strategyLabel, cfgExp.montecarlo.strength, nExpected);

    for mi = 1:nM
        mName = metrics{mi};
        for si = 1:nSc
            sc    = scenarios{si};
            scDef = cfgExp.scenarios.(sc);
            mask  = strcmpi(T.scenario, sc) & ...
                    strcmpi(T.strategy_code, cfgExp.montecarlo.strategyCode) & ...
                    abs(T.strength - cfgExp.montecarlo.strength) < 1e-9;
            vals  = T.(mName)(mask);
            assert(numel(vals) == nExpected, 'plot_results:incompleteMCCell', ...
                'Expected %d rows for %s/%s, found %d.', nExpected, mName, sc, numel(vals));
            mu = mean(vals);
            sd = std(vals);
            ci = zVal * sd / sqrt(numel(vals));
            means(mi, si) = mu;
            stds(mi, si)  = sd;
            cis(mi, si)   = ci;
            fprintf('  %-6s | %-5s | mean = %.4f (%.6f) | 95%% CI = [%.4f, %.4f] | SD = %.6f\n', ...
                mName, scDef.label, mu, mu, mu - ci, mu + ci, sd);
        end
    end

    hFig = figure('Name', 'Figure 3: Monte Carlo Summary Metrics', 'Color', 'w', ...
        'Visible', 'off', 'Position', [100, 100, 900, 560]);
    try hFig.Theme = 'light'; catch, end
    tl = tiledlayout(hFig, 1, 1, 'Padding', 'compact');
    ax = nexttile(tl);
    hold(ax, 'on');

    colors  = {[0.18, 0.48, 0.72], [0.82, 0.36, 0.18]};
    markers = {'o', 's'};
    offsets = [-0.14, 0.14];

    for mi = 1:(nM - 1)
        xline(ax, mi + 0.5, ':', 'Color', [0.82, 0.82, 0.82], 'LineWidth', 1.0, 'HandleVisibility', 'off');
    end

    legendHandles = gobjects(1, nSc);
    for si = 1:nSc
        scDef = cfgExp.scenarios.(scenarios{si});
        xPos  = (1:nM) + offsets(si);
        col   = colors{si};
        for mi = 1:nM
            mu = means(mi, si);
            ci = cis(mi, si);
            plot(ax, [xPos(mi), xPos(mi)], [mu - ci, mu + ci], '-', ...
                'Color', col, 'LineWidth', 2.2, 'HandleVisibility', 'off');
        end
        legendHandles(si) = plot(ax, xPos, means(:, si), markers{si}, ...
            'LineStyle', 'none', 'MarkerSize', 8.5, ...
            'MarkerFaceColor', col, 'MarkerEdgeColor', [0 0 0], 'LineWidth', 0.8, ...
            'DisplayName', scDef.label);
    end

    for mi = 1:nM
        for si = 1:nSc
            mu = means(mi, si);
            xTxt = mi + offsets(si) + sign(offsets(si)) * 0.045;
            if offsets(si) < 0
                hAlign = 'right';
            else
                hAlign = 'left';
            end
            text(ax, xTxt, mu, sprintf('%.3f', mu), ...
                'HorizontalAlignment', hAlign, 'VerticalAlignment', 'middle', ...
                'FontSize', 10, 'FontWeight', 'bold', 'Color', [0 0 0], ...
                'BackgroundColor', [1 1 1], 'Margin', 1.5);
        end
    end

    set(ax, 'XTick', 1:nM, 'XTickLabel', metrics, 'TickLabelInterpreter', 'none', ...
        'YTick', yBounds(1):0.05:yBounds(2), 'FontSize', 11, 'FontWeight', 'bold');
    xlim(ax, [0.40, nM + 0.60]);
    ylim(ax, yBounds);
    ylabel(ax, 'Score (higher is better)', 'FontWeight', 'bold', 'Interpreter', 'none');
    title(tl, sprintf('Monte Carlo summary: mean ± 95%% CI over %d runs (%s, strength %.2f)', ...
        nExpected, cfgExp.montecarlo.strategyLabel, cfgExp.montecarlo.strength), ...
        'FontSize', 13.5, 'FontWeight', 'bold', 'Color', [0 0 0], 'Interpreter', 'none');
    xlabel(tl, 'R_time is affected by the queue-pruning artifact under realistic_local (see README); read it with care.', ...
        'FontSize', 9, 'Color', [0.25 0.25 0.25], 'Interpreter', 'none');

    lg = legend(ax, legendHandles, 'Location', 'northeast', 'Box', 'on', 'FontSize', 10);
    lg.Color = [1 1 1]; lg.TextColor = [0 0 0]; lg.EdgeColor = [0.6 0.6 0.6];
    grid(ax, 'on');
    styleCleanAxes(ax);

    files = saveFigurePng(hFig, outDir, 'fig3_mc_metrics', cfgExp.plotting.dpi);
end

%% ======================= FIGURE 4: CRI VS ATTACK =======================

function files = plotFig4CriVsAttack(T, cfgExp, outDir)
    scenarios   = cfgExp.scenarios.names;
    stratLabels = {cfgExp.strategies.label};
    stratCodes  = {cfgExp.strategies.code};
    strengths   = cfgExp.attack.strengths;
    nSc         = numel(scenarios);
    nSt         = numel(stratCodes);
    nC          = numel(strengths);
    nReps       = cfgExp.attack.nReps;
    tCrit       = 2.04523; % t-distribution, df = 29, two-sided 95% CI

    means = zeros(nSc, nSt, nC);
    cis   = zeros(nSc, nSt, nC);

    fprintf('\n--- Figure 4: CRI vs Payload Slots Lost (t = %.5f, df = %d, n = %d) ---\n', ...
        tCrit, nReps - 1, nReps);
    fprintf('  %-5s | %-8s | %-5s | %-8s | %-10s | %-10s\n', ...
        'Scen', 'Strategy', 'Slots', 'Strength', 'Mean CRI', '95% CI (+/-)');

    for si = 1:nSc
        sc    = scenarios{si};
        scDef = cfgExp.scenarios.(sc);
        slots = cfgExp.attack.realisedSlots.(sc);
        for ri = 1:nSt
            for ci = 1:nC
                mask = strcmpi(T.scenario, sc) & ...
                       strcmpi(T.strategy_code, stratCodes{ri}) & ...
                       abs(T.strength - strengths(ci)) < 1e-9;
                vals = T.CRI(mask);
                assert(numel(vals) == nReps, 'plot_results:missingAttackCell', ...
                    'Expected %d runs for %s/%s/%.2f, got %d.', ...
                    nReps, sc, stratCodes{ri}, strengths(ci), numel(vals));
                mu = mean(vals);
                sd = std(vals);
                hw = tCrit * sd / sqrt(nReps);
                means(si, ri, ci) = mu;
                cis(si, ri, ci)   = hw;
                fprintf('  %-5s | %-8s | %-5d | %-8.2f | %-10.6f | %-10.6f\n', ...
                    scDef.label, stratLabels{ri}, slots(ci), strengths(ci), mu, hw);
            end
            seq = squeeze(means(si, ri, :));
            assert(all(diff(seq) < 0), 'plot_results:nonMonotoneCRI', ...
                'CRI is not strictly decreasing for %s / %s: [%s]', ...
                scDef.label, stratLabels{ri}, num2str(seq', '%.6f '));
        end
    end
    fprintf('  Monotonicity check: all 6 (scenario x strategy) sequences strictly decreasing.\n');

    hFig = figure('Name', 'Figure 4: CRI vs Payload Slots Lost', 'Color', 'w', ...
        'Visible', 'off', 'Position', [80, 80, 1220, 560]);
    try hFig.Theme = 'light'; catch, end
    tl = tiledlayout(hFig, 1, nSc, 'Padding', 'compact', 'TileSpacing', 'compact');
    title(tl, 'CRI decreases as more payload slots are lost (Random, Balanced, Direct; mean ± 95% CI, 30 seeds)', ...
        'FontSize', 13, 'FontWeight', 'bold', 'Color', [0 0 0], 'Interpreter', 'none');
    xlabel(tl, { ...
        'Attacks are drawn across the timing window [0.15, 0.60] of the horizon, not applied one after another in time.', ...
        '''Slots lost'' is the number of failed (UAV, payload) slots. CRI is affected by the queue-pruning artifact under realistic_local (see README).'}, ...
        'FontSize', 9, 'Color', [0.25 0.25 0.25], 'Interpreter', 'none');

    colors  = {[0.18, 0.48, 0.72], [0.18, 0.58, 0.42], [0.82, 0.36, 0.18]};
    markers = {'o', 's', '^'};
    dodges  = {[-0.08, 0, 0.08], [-0.16, 0, 0.16]};

    for si = 1:nSc
        sc    = scenarios{si};
        scDef = cfgExp.scenarios.(sc);
        slots = cfgExp.attack.realisedSlots.(sc);
        ax    = nexttile(tl, si);
        hold(ax, 'on');

        for ri = 1:nSt
            xVals = slots + dodges{si}(ri);
            yVals = squeeze(means(si, ri, :))';
            eVals = squeeze(cis(si, ri, :))';
            errorbar(ax, xVals, yVals, eVals, ['-' markers{ri}], ...
                'Color', colors{ri}, 'LineWidth', 1.8, ...
                'MarkerSize', 7.5, 'MarkerFaceColor', colors{ri}, ...
                'CapSize', 5, 'DisplayName', stratLabels{ri});
        end

        xTicks = slots;
        xTickLabels = cell(1, nC);
        for ci = 1:nC
            xTickLabels{ci} = sprintf('%d\\newline(%.2f)', slots(ci), strengths(ci));
        end
        set(ax, 'XTick', xTicks, 'XTickLabel', xTickLabels, ...
            'YTick', 0.4:0.05:0.8, 'FontSize', 10.5, 'FontWeight', 'bold');
        xlim(ax, [min(slots) - 0.65, max(slots) + 0.65]);
        ylim(ax, [0.4, 0.8]);
        xlabel(ax, 'Payload slots lost (interruption strength)', 'FontWeight', 'bold');
        if si == 1
            ylabel(ax, 'CRI (higher is better)', 'FontWeight', 'bold');
        end
        title(ax, sprintf('%s (%d UAVs, %d tasks)', scDef.label, scDef.nUAV, scDef.nTasks), ...
            'FontSize', 12, 'FontWeight', 'bold', 'Color', [0 0 0]);
        lg = legend(ax, 'Location', 'northeast', 'Box', 'on', 'FontSize', 9.5);
        lg.Color = [1 1 1]; lg.TextColor = [0 0 0]; lg.EdgeColor = [0.6 0.6 0.6];
        grid(ax, 'on');
        styleCleanAxes(ax);
    end

    files = saveFigurePng(hFig, outDir, 'fig4_cri_vs_attack', cfgExp.plotting.dpi);
end

%% ======================= HELPERS =======================

function styleCleanAxes(ax)
    ax.Color     = [1 1 1];
    ax.XColor    = [0 0 0];
    ax.YColor    = [0 0 0];
    ax.GridColor = [0.80 0.80 0.80];
    box(ax, 'on');
end

function files = saveFigurePng(hFig, outDir, baseName, dpi)
    pngPath = fullfile(outDir, [baseName, '.png']);
    exportgraphics(hFig, pngPath, 'Resolution', dpi);
    close(hFig);
    files = {pngPath};
end
