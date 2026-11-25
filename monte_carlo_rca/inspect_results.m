%% INSPECT_RESULTS
% Displays formatted tables of BDTR Before vs. Exact Paper Monte Carlo results.
%
% Usage:
%   inspect_results

function inspect_results()
    baseDir = fileparts(mfilename('fullpath'));
    summaryCsv = fullfile(baseDir, 'results', 'csv', 'bdtr_comparison_summary.csv');

    if ~exist(summaryCsv, 'file')
        error('inspect_results:noCsv', 'No summary CSV found at: %s. Run run_bdtr_comparison first.', summaryCsv);
    end

    T = readtable(summaryCsv);

    fprintf('\n===================================================================================================\n');
    fprintf('                      BDTR SUMMARY RESULTS: BEFORE vs. EXACT PAPER\n');
    fprintf('===================================================================================================\n\n');

    fprintf('%-16s %-10s %16s %14s %10s %10s %10s\n', ...
        'Profile', 'Scenario', 'Completion %', 'Failed %', 'CRI', 'R_task', 'R_time');
    fprintf('%s\n', repmat('-', 1, 95));

    for i = 1:height(T)
        prof = string(T.Profile{i});
        sc = string(T.Scenario{i});
        comp = sprintf('%.2f ± %.2f%%', T.CompletionMean_pct(i), T.CompletionStd_pct(i));
        fail = sprintf('%.2f%%', T.FailedMean_pct(i));
        cri = sprintf('%.3f', T.CRIMean(i));
        rtask = sprintf('%.3f', T.RtaskMean(i));
        rtime = sprintf('%.3f', T.RtimeMean(i));

        fprintf('%-16s %-10s %16s %14s %10s %10s %10s\n', prof, sc, comp, fail, cri, rtask, rtime);
    end
    fprintf('%s\n', repmat('=', 1, 95));
    fprintf('Scorecard image: results/png/bdtr_before_vs_exact_paper.png\n\n');
end
