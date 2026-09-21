function plot_summary_scorecards()
% PLOT_SUMMARY_SCORECARDS  One readable scorecard image per experiment.
%
% Reads the saved CSVs in results/csv/ (no rerun) and writes:
%   results/png/mc_summary_scorecard.png
%   results/png/attack_summary_scorecard.png

    thisDir = fileparts(mfilename('fullpath'));
    addpath(thisDir);

    methodOrder = {'RRAM', 'BDTR', 'SROM', 'Hungarian'};
    methodColors = [ ...
        0.45, 0.45, 0.45; ...
        0.85, 0.33, 0.10; ...
        0.00, 0.45, 0.74; ...
        0.47, 0.67, 0.19];

    mcCsv = results_locate('csv', 'mc_summary_metrics.csv');
    atkCsv = results_locate('csv', 'attack_summary_metrics.csv');
    if ~exist(mcCsv, 'file') || ~exist(atkCsv, 'file')
        error('plot_summary_scorecards:noCsv', ...
            'Need mc_summary_metrics.csv and attack_summary_metrics.csv in results/csv/.');
    end

    pngDir = results_paths().png;
    plotMonteCarloScorecard(mcCsv, pngDir, methodOrder);
    plotAttackScorecard(atkCsv, pngDir, methodOrder, methodColors);
end

function plotMonteCarloScorecard(mcCsv, pngDir, methodOrder)
    T = readtable(mcCsv);
    T.ShortName = shortenMethodNames(T.Algorithm);

    metricKeys = {'CompRate_Mean_pct', 'CRI_Mean', 'R_task_Mean', 'R_time_Mean', 'ThrptRecov_Mean'};
    metricLabels = {'Completion %', 'CRI', 'R_{task}', 'R_{time}', 'Salvage'};
    isPercent = [true, false, false, false, false];
    scenarios = {'small', 'large'};
    scTitles = { ...
        'Small  (5 UAVs, 2 payloads, 80 tasks)', ...
        'Large  (10 UAVs, 3 payloads, 120 tasks)'};

    hFig = figure('Name', 'Experiment B: Monte Carlo summary', ...
        'Color', 'w', 'Visible', 'off', 'Position', [80, 80, 1480, 860]);
    tl = tiledlayout(hFig, 2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
    title(tl, 'Experiment B  —  Monte Carlo summary   (N = 300,  30% random payload attack)', ...
        'FontSize', 15, 'FontWeight', 'bold', 'Color', [0 0 0]);

    for sc = 1:2
        sub = T(strcmp(string(T.Scenario), scenarios{sc}), :);
        sub = sortMethods(sub, methodOrder);
        nM = height(sub);
        vals = zeros(nM, numel(metricKeys));
        for k = 1:numel(metricKeys)
            vals(:, k) = sub.(metricKeys{k});
        end

        axBar = nexttile(tl);
        plotGroupedMetricBars(axBar, sub.ShortName, vals, isPercent, metricLabels);
        title(axBar, scTitles{sc}, 'FontSize', 12, 'FontWeight', 'bold', 'Color', [0 0 0]);
        if sc == 1
            lg = legend(axBar, metricLabels, 'Location', 'southoutside', 'Orientation', 'horizontal', ...
                'Box', 'off', 'FontSize', 9);
            lg.TextColor = [0 0 0];
        end

        axTab = nexttile(tl);
        cellText = formatScoreCells(vals, isPercent);
        drawScoreTable(axTab, sub.ShortName, metricLabels, vals, cellText, ...
            sprintf('%s  —  mean of 300 runs', scTitles{sc}));
    end

    figPath = fullfile(pngDir, 'mc_summary_scorecard.png');
    exportScorecard(hFig, figPath);
end

function plotAttackScorecard(atkCsv, pngDir, methodOrder, methodColors)
    T = readtable(atkCsv);
    T.ShortName = shortenMethodNames(T.Algorithm);
    strengths = [20, 30, 40];
    scenarios = {'small', 'large'};
    scTitles = { ...
        'Small  (5 UAVs, 80 tasks)', ...
        'Large  (10 UAVs, 120 tasks)'};

    hFig = figure('Name', 'Experiment A: Attack summary', ...
        'Color', 'w', 'Visible', 'off', 'Position', [80, 80, 1480, 920]);
    tl = tiledlayout(hFig, 2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
    title(tl, {'Experiment A  —  Attack-sweep summary', ...
        'Each cell is the mean across Random / Balanced / Directed  (10 trials each)'}, ...
        'FontSize', 14, 'FontWeight', 'bold', 'Color', [0 0 0]);

    for sc = 1:2
        sub = T(strcmp(string(T.Scenario), scenarios{sc}), :);
        names = methodOrder(:);
        nM = numel(names);
        nS = numel(strengths);
        comp = nan(nM, nS);
        cri = nan(nM, nS);
        for mi = 1:nM
            for si = 1:nS
                mask = strcmp(sub.ShortName, names{mi}) & sub.Strength_pct == strengths(si);
                comp(mi, si) = mean(sub.completionRate_Mean(mask), 'omitnan') * 100;
                cri(mi, si) = mean(sub.CRI_Mean(mask), 'omitnan');
            end
        end

        axBar = nexttile(tl);
        x = 1:nS;
        b = bar(axBar, x, comp', 'grouped');
        for mi = 1:nM
            b(mi).FaceColor = methodColors(mi, :);
            b(mi).EdgeColor = 'none';
            b(mi).FaceAlpha = 0.92;
            xt = b(mi).XEndPoints;
            yt = b(mi).YEndPoints;
            for k = 1:numel(xt)
                text(axBar, xt(k), yt(k) + 1.2, sprintf('%.0f', yt(k)), ...
                    'HorizontalAlignment', 'center', 'FontSize', 8, 'Color', [0.15 0.15 0.15]);
            end
        end
        hold(axBar, 'on'); grid(axBar, 'on'); box(axBar, 'on');
        styleBlackAxes(axBar);
        set(axBar, 'XTick', x, 'XTickLabel', {'20%', '30%', '40%'}, 'FontSize', 10);
        ylim(axBar, [0, 80]);
        ylabel(axBar, 'Completion %', 'FontWeight', 'bold');
        xlabel(axBar, 'Interruption strength');
        title(axBar, sprintf('%s  —  completion', scTitles{sc}), 'FontSize', 12, 'FontWeight', 'bold', 'Color', [0 0 0]);
        if sc == 1
            lg = legend(axBar, names, 'Location', 'southoutside', 'Orientation', 'horizontal', ...
                'Box', 'off', 'FontSize', 9);
            lg.TextColor = [0 0 0];
        end

        axTab = nexttile(tl);
        both = [comp, cri];
        colLabels = {'Comp 20%', 'Comp 30%', 'Comp 40%', 'CRI 20%', 'CRI 30%', 'CRI 40%'};
        isPercent = [true, true, true, false, false, false];
        cellText = formatScoreCells(both, isPercent);
        drawScoreTable(axTab, names, colLabels, both, cellText, ...
            sprintf('%s  —  completion and CRI', scTitles{sc}));
    end

    figPath = fullfile(pngDir, 'attack_summary_scorecard.png');
    exportScorecard(hFig, figPath);
end

function plotGroupedMetricBars(ax, names, vals, isPercent, metricLabels)
    nM = size(vals, 1);
    nK = size(vals, 2);
    scaled = vals;
    for k = 1:nK
        if ~isPercent(k)
            scaled(:, k) = vals(:, k) * 100;
        end
    end
    x = 1:nM;
    b = bar(ax, x, scaled, 'grouped');
    palette = [ ...
        0.20, 0.45, 0.70; ...
        0.85, 0.40, 0.15; ...
        0.15, 0.60, 0.45; ...
        0.55, 0.35, 0.70; ...
        0.70, 0.55, 0.15];
    for k = 1:nK
        b(k).FaceColor = palette(k, :);
        b(k).EdgeColor = 'none';
        b(k).FaceAlpha = 0.92;
        b(k).DisplayName = metricLabels{k};
        xt = b(k).XEndPoints;
        yt = b(k).YEndPoints;
        for i = 1:numel(xt)
            if isPercent(k)
                lab = sprintf('%.0f', yt(i));
            else
                lab = sprintf('%.2f', yt(i) / 100);
            end
            text(ax, xt(i), yt(i) + 1.6, lab, ...
                'HorizontalAlignment', 'center', 'FontSize', 7.5, 'Color', [0.15 0.15 0.15]);
        end
    end
    hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
    styleBlackAxes(ax);
    set(ax, 'XTick', x, 'XTickLabel', names, 'FontSize', 10);
    ylim(ax, [0, 105]);
    ylabel(ax, 'Value  (rates in %,  indices ×100 on bars)', 'FontWeight', 'bold');
end

function drawScoreTable(ax, rowLabels, colLabels, vals, cellText, axTitle)
    [nR, nC] = size(vals);
    bg = ones(nR, nC, 3);
    winColor = [0.72, 0.88, 0.62];
    for c = 1:nC
        mx = max(vals(:, c));
        hits = abs(vals(:, c) - mx) <= 1e-9;
        for r = 1:nR
            if hits(r)
                bg(r, c, 1) = winColor(1);
                bg(r, c, 2) = winColor(2);
                bg(r, c, 3) = winColor(3);
            end
        end
    end

    image(ax, bg);
    hold(ax, 'on');
    for xg = 0.5:1:(nC + 0.5)
        plot(ax, [xg xg], [0.5, nR + 0.5], 'Color', [0.78 0.78 0.78], 'LineWidth', 0.6);
    end
    for yg = 0.5:1:(nR + 0.5)
        plot(ax, [0.5, nC + 0.5], [yg yg], 'Color', [0.78 0.78 0.78], 'LineWidth', 0.6);
    end
    axis(ax, 'tight');
    set(ax, 'XTick', 1:nC, 'XTickLabel', colLabels, ...
        'YTick', 1:nR, 'YTickLabel', rowLabels, ...
        'TickLength', [0 0], 'FontSize', 11, 'FontWeight', 'bold', ...
        'YDir', 'reverse', 'XTickLabelRotation', 0);
    xlim(ax, [0.5, nC + 0.5]);
    ylim(ax, [0.5, nR + 0.5]);
    styleBlackAxes(ax);
    ax.GridLineStyle = 'none';
    title(ax, axTitle, 'FontSize', 11, 'FontWeight', 'bold', 'Color', [0 0 0]);
    for r = 1:nR
        for c = 1:nC
            text(ax, c, r, cellText{r, c}, 'HorizontalAlignment', 'center', ...
                'FontSize', 11, 'FontWeight', 'bold', 'Color', [0 0 0]);
        end
    end
end

function styleBlackAxes(ax)
    ax.Color = [1 1 1];
    ax.XColor = [0 0 0];
    ax.YColor = [0 0 0];
    ax.GridColor = [0.78 0.78 0.78];
    ax.Title.Color = [0 0 0];
    if isprop(ax, 'XAxis')
        ax.XAxis.Color = [0 0 0];
        ax.YAxis.Color = [0 0 0];
        ax.XAxis.TickLabelColor = [0 0 0];
        ax.YAxis.TickLabelColor = [0 0 0];
    end
end

function names = shortenMethodNames(raw)
    names = string(raw);
    names = replace(names, 'Hungarian (Ours)', 'Hungarian');
    names = cellstr(names);
end

function sub = sortMethods(sub, methodOrder)
    idx = zeros(numel(methodOrder), 1);
    for i = 1:numel(methodOrder)
        hit = find(strcmp(sub.ShortName, methodOrder{i}), 1);
        if isempty(hit)
            error('plot_summary_scorecards:missingMethod', 'No row for %s', methodOrder{i});
        end
        idx(i) = hit;
    end
    sub = sub(idx, :);
end

function C = formatScoreCells(vals, isPercent)
    [nR, nC] = size(vals);
    C = cell(nR, nC);
    for r = 1:nR
        for c = 1:nC
            if isPercent(c)
                C{r, c} = sprintf('%.1f%%', vals(r, c));
            else
                C{r, c} = sprintf('%.3f', vals(r, c));
            end
        end
    end
end

function exportScorecard(hFig, figPath)
    try
        exportgraphics(hFig, figPath, 'Resolution', 160);
    catch
        saveas(hFig, figPath);
    end
    close(hFig);
    fprintf('Wrote %s\n', figPath);
end
