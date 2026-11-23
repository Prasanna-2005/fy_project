function fpath = results_file(kind, name)
% RESULTS_FILE  Nested write path under results/<kind>/.
% KIND is 'png', 'csv', 'mat', or 'log'.

    p = results_paths();
    if ~isfield(p, kind)
        error('results_file:badKind', 'Unknown results kind "%s".', kind);
    end
    fpath = fullfile(p.(kind), name);
end
