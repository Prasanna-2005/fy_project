function cfg = apply_v2_profile(cfg, profile)
% APPLY_V2_PROFILE  Declare experimental assumptions explicitly.
%
% 'paper_aligned' removes the two mechanisms that the BDTR paper says are
% excluded from its numerical experiments: flight time and communication
% latency. This codebase has no communication simulator. The paper supplies
% no per-task deadlines, so deadlines are set to Inf rather than invented.
%
% 'realistic_local' retains the legacy project assumptions: 5 m/s travel and
% locally constructed finite deadlines. It is an extension experiment, not a
% reproduction of Zeng et al. (2026).

if nargin < 2 || isempty(profile)
    profile = 'paper_aligned';
end

profile = lower(string(profile));
switch profile
    case "paper_aligned"
        cfg.sim.includeTravel = false;
        for j = 1:numel(cfg.task)
            cfg.task(j).deadline = Inf;
        end
        cfg.v2.profile = 'paper_aligned';
        cfg.v2.description = ['Paper-constraint-aligned: no flight time, no ' ...
            'invented deadlines. Task locations, execution times, horizon, ' ...
            'and attack schedule remain locally specified because the paper omits them.'];
    case "realistic_local"
        cfg.sim.includeTravel = true;
        cfg.v2.profile = 'realistic_local';
        cfg.v2.description = ['Local extension: 5 m/s geometric travel and ' ...
            'constructed task deadlines are enabled. Not a paper reproduction.'];
    otherwise
        error('apply_v2_profile:unknownProfile', ...
            'Unknown V2 profile "%s".', profile);
end
end
