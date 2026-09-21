function fpath = results_locate(kind, name)
% RESULTS_LOCATE  Find a results artifact. Prefers results/<kind>/name,
% then a leftover flat copy in results/.

    nested = results_file(kind, name);
    if exist(nested, 'file')
        fpath = nested;
        return;
    end
    p = results_paths();
    old = fullfile(p.root, name);
    if exist(old, 'file')
        fpath = old;
        return;
    end
    fpath = nested;
end
