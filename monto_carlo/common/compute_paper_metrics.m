function pm = compute_paper_metrics(tasks, events, cfg, tEnd)
% COMPUTE_PAPER_METRICS  Compute BDTR paper's reported metrics.
%   These are the actual metrics from the BDTR paper (Zeng et al. 2026)
%   needed to compare against reported values (0.829/0.862 for BDTR).
%
%   Returns struct with:
%     R_task            - Task completion ratio (completed / total)
%     R_time            - Normalized time margin (how much deadline slack remained)
%     CRI               - Comprehensive Resilience Index = alpha*R_task + (1-alpha)*R_time
%     throughputRecovery- Completed tasks after first attack / total tasks

    if nargin < 4
        tEnd = cfg.sim.tEnd;
    end

    alpha = 0.5; % default
    if isfield(cfg, 'bdtr') && isfield(cfg.bdtr, 'alpha')
        alpha = cfg.bdtr.alpha;
    end

    nT = numel(tasks);

    % ---- R_task: fraction of tasks completed ----
    nComplete = sum(strcmp({tasks.status}, 'complete'));
    pm.R_task = nComplete / nT;

    % ---- R_time: normalized remaining time margin for completed tasks ----
    % R_time = mean((deadline - completeTime) / deadline) for completed tasks
    % Higher = tasks finished with more deadline slack = better
    completedIdx = find(strcmp({tasks.status}, 'complete'));
    if isempty(completedIdx)
        pm.R_time = 0;
    else
        margins = zeros(1, numel(completedIdx));
        for k = 1:numel(completedIdx)
            j = completedIdx(k);
            dl = tasks(j).deadline;
            ct = tasks(j).completeTime;
            if dl > 0
                margins(k) = max(0, (dl - ct)) / dl;
            else
                margins(k) = 0;
            end
        end
        pm.R_time = mean(margins);
    end

    % ---- CRI: Comprehensive Resilience Index ----
    pm.CRI = alpha * pm.R_task + (1 - alpha) * pm.R_time;

    % ---- Throughput Recovery ----
    % = tasks completed after the first attack / total tasks
    % Find the first attack event time
    firstAttackTime = tEnd; % default: if no attack, use tEnd
    if ~isempty(events)
        for e = 1:numel(events)
            if strcmp(events(e).trigger, 'degradation')
                firstAttackTime = events(e).time;
                break;
            end
        end
    end

    % Count tasks that completed after the first attack
    nPostAttack = 0;
    for j = 1:nT
        if strcmp(tasks(j).status, 'complete') && tasks(j).completeTime >= firstAttackTime
            nPostAttack = nPostAttack + 1;
        end
    end
    % Throughput recovery is relative to total tasks
    pm.throughputRecovery = nPostAttack / nT;

end
