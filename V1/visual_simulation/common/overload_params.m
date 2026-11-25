function [delta, nomCap] = overload_params(cfg)
% OVERLOAD_PARAMS  Shared overload slowdown used by every method.
% Zeng et al. stretch execution by 1/delta when a queue exceeds nominal
% capacity. Keeping this in one place stops BDTR from being the only
% method that pays the penalty.
delta = 0.9;
nomCap = 3;
if nargin >= 1 && isstruct(cfg) && isfield(cfg, 'bdtr')
    if isfield(cfg.bdtr, 'delta') && ~isempty(cfg.bdtr.delta)
        delta = cfg.bdtr.delta;
    end
    if isfield(cfg.bdtr, 'nominalCapacity') && ~isempty(cfg.bdtr.nominalCapacity)
        nomCap = cfg.bdtr.nominalCapacity;
    end
end
end
