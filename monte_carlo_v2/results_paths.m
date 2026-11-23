function p = results_paths()
% RESULTS_PATHS  Typed subfolders under monte_carlo/results/.
%
%   results/png/   plots
%   results/csv/   tables
%   results/mat/   MATLAB archives
%   results/log/   batch logs

    thisDir = fileparts(mfilename('fullpath'));
    p.root = fullfile(thisDir, 'results');
    p.png  = fullfile(p.root, 'png');
    p.csv  = fullfile(p.root, 'csv');
    p.mat  = fullfile(p.root, 'mat');
    p.log  = fullfile(p.root, 'log');

    dirs = {p.root, p.png, p.csv, p.mat, p.log};
    for i = 1:numel(dirs)
        if ~exist(dirs{i}, 'dir')
            mkdir(dirs{i});
        end
    end
end
