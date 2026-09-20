function pm = compute_paper_metrics(tasks, events, cfg, tEnd)
% COMPUTE_PAPER_METRICS  Compute BDTR paper's reported resilience metrics.
%   Formulas aligned with Zeng et al. (2026):
%     - R_task: Task Completion Resilience (Eq. 5)
%               R_task = (sum(Omega) + gamma * N_realloc) / (lambda_max * Delta_t)
%     - R_time: Time Efficiency Resilience (Eq. 6)
%               R_time = 1 - T_recover / (t_end - t_start)
%     - CRI:    Comprehensive Resilience Index
%               CRI = alpha * R_task + (1 - alpha) * R_time
%     - ThroughputRecovery: Task salvage amount relative to do-nothing baseline
%
%   Inputs:
%     tasks  - array of task structs
%     events - array of simulation event structs
%     cfg    - scenario config struct
%     tEnd   - simulation horizon (s)

    if nargin < 4
        tEnd = cfg.sim.tEnd;
    end

    alpha = 0.5;
    if isfield(cfg, 'bdtr') && isfield(cfg.bdtr, 'alpha')
        alpha = cfg.bdtr.alpha;
    end

    gamma = 0.5;
    if isfield(cfg, 'bdtr') && isfield(cfg.bdtr, 'gamma')
        gamma = cfg.bdtr.gamma;
    end

    nT = numel(tasks);

    % =========================================================================
    % 1. IDENTIFY DISRUPTION WINDOW & AT-RISK TASKS (DO-NOTHING BASELINE)
    % =========================================================================
    % Find all degradation events
    isDegradation = strcmp({events.trigger}, 'degradation');
    degEvents = events(isDegradation);

    if isempty(degEvents)
        % No disruption occurred: perfect resilience
        nComplete = sum(strcmp({tasks.status}, 'complete'));
        pm.R_task = nComplete / max(1, nT);
        pm.R_time = 1.0;
        pm.CRI = alpha * pm.R_task + (1 - alpha) * pm.R_time;
        pm.throughputRecovery = 1.0;
        return;
    end

    tStart = min([degEvents.time]);

    % Find steady-state mission finish time
    completedMask = strcmp({tasks.status}, 'complete');
    if any(completedMask)
        tEndActual = max([tasks(completedMask).completeTime]);
    else
        tEndActual = tEnd;
    end
    tEndWindow = max(tStart + 1, min(tEnd, tEndActual));
    deltaT = tEndWindow - tStart;

    % =========================================================================
    % 2. IDENTIFY AT-RISK TASKS FROM DEGRADATIONS (DO-NOTHING COUNTERFACTUAL)
    % =========================================================================
    % An at-risk task is any task that was assigned to a UAV suffering capability
    % loss where the task requires that specific capability. Under "do-nothing",
    % all such tasks fail.
    atRiskTaskIDs = [];
    for d = 1:numel(degEvents)
        evD = degEvents(d);
        uFail = evD.newUAV; % degraded UAV index
        capLost = evD.reason; % lost capability name
        tDeg = evD.time;

        % Check which tasks were on uFail at tDeg requiring capLost
        for j = 1:nT
            if ismember(capLost, tasks(j).requiredCap)
                % Check if this task was affected on this UAV
                % If event log shows a reallocation from uFail at tDeg:
                evMatch = events([events.oldUAV] == uFail & [events.taskIdx] == j & [events.time] >= tDeg);
                if ~isempty(evMatch)
                    atRiskTaskIDs = unique([atRiskTaskIDs, j]);
                end
            end
        end
    end

    % If atRiskTaskIDs empty from event diff, check tasks flagged 'atrisk' or reallocated
    if isempty(atRiskTaskIDs)
        reallocPostAttack = events([events.time] >= tStart & [events.oldUAV] > 0 & [events.taskIdx] > 0);
        atRiskTaskIDs = unique([reallocPostAttack.taskIdx]);
    end

    nAtRisk = numel(atRiskTaskIDs);

    % =========================================================================
    % 3. R_TIME (Eq. 6): System-level recovery speed measure
    %    R_time = 1 - T_recover / Delta_t
    % =========================================================================
    % T_recover is the duration from tStart until all reallocated tasks complete
    if nAtRisk == 0
        T_recover = 0;
    else
        reallocCompleted = atRiskTaskIDs(strcmp({tasks(atRiskTaskIDs).status}, 'complete'));
        if ~isempty(reallocCompleted)
            tSteady = max([tasks(reallocCompleted).completeTime]);
            T_recover = max(0, tSteady - tStart);
        else
            T_recover = deltaT; % Failed to recover before window closed
        end
    end
    T_recover = min(T_recover, deltaT);
    pm.R_time = max(0, 1 - (T_recover / deltaT));

    % =========================================================================
    % 4. R_TASK (Eq. 5): Task completion resilience with reallocation gain gamma
    %    R_task = (sum(Omega) + gamma * N_realloc) / (lambda_max * Delta_t)
    % =========================================================================
    % Omega(q) = task priority (value)
    % N_realloc = number of successfully completed reallocated tasks
    taskValues = [tasks.priority];
    totalTaskValue = sum(taskValues);

    completedValues = sum([tasks(completedMask).priority]);

    % Count successfully completed reallocations
    salvagedTasks = atRiskTaskIDs(strcmp({tasks(atRiskTaskIDs).status}, 'complete'));
    nRealloc = numel(salvagedTasks);

    % Denominator: maximum theoretical return (all tasks + all needed reallocations)
    maxTheoreticalValue = totalTaskValue + gamma * max(1, nAtRisk);
    achievedValue = completedValues + gamma * nRealloc;

    pm.R_task = min(1.0, achievedValue / maxTheoreticalValue);

    % =========================================================================
    % 5. THROUGHPUT RECOVERY (relative to Do-Nothing baseline)
    %    Salvage ratio of at-risk tasks saved by the reallocation method
    % =========================================================================
    if nAtRisk > 0
        pm.throughputRecovery = numel(salvagedTasks) / nAtRisk;
    else
        pm.throughputRecovery = 1.0;
    end

    % =========================================================================
    % 6. CRI: Comprehensive Resilience Index
    % =========================================================================
    pm.CRI = alpha * pm.R_task + (1 - alpha) * pm.R_time;
end
