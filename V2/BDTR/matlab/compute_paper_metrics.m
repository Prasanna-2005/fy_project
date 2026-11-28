function pm = compute_paper_metrics(tasks, events, cfg, tEnd)
% COMPUTE_PAPER_METRICS  Zeng et al. (IEEE Systems Journal, 2026) Eqs. 5–7.
%
%   R_task  (Eq. 5): (sum Omega + gamma * N_realloc) / denom
%   R_time  (Eq. 6): 1 - T_recover / (t_end - t_start)
%            T_recover is time from the first payload failure to a new
%            swarm-throughput equilibrium AFTER the last failure — not
%            "time until the last salvaged task completes".
%   CRI     (Eq. 7): alpha * R_task + (1-alpha) * R_time
%
%   throughputRecovery: salvage fraction of the true at-risk set
%            (tasks queued on a degraded UAV that required the lost
%            payload). This is in [0, 1]. It is NOT Zeng et al. Fig. 6(b),
%            which is a do-nothing throughput delta and can exceed 1.
%
%   At-risk tasks are recovered by replaying the assignment log up to
%   each degradation event. This does not depend on whether a method
%   logs oldUAV = failed UAV (BDTR/RRAM/SROM) or zeros assignedUAV
%   before logging (Hungarian).

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
    completedMask = strcmp({tasks.status}, 'complete');

    isDegradation = strcmp({events.trigger}, 'degradation');
    degEvents = events(isDegradation);

    if isempty(degEvents)
        nComplete = sum(completedMask);
        pm.R_task = nComplete / max(1, nT);
        pm.R_time = 1.0;
        pm.CRI = alpha * pm.R_task + (1 - alpha) * pm.R_time;
        pm.throughputRecovery = 1.0;
        pm.nAtRisk = 0;
        pm.nSalvaged = 0;
        pm.T_recover = 0;
        pm.deltaT = 0;
        return;
    end

    tStart = min([degEvents.time]);
    tLastDeg = max([degEvents.time]);
    deltaT = max(1, tEnd - tStart);

    % =====================================================================
    % At-risk set: assignment state at each degradation, BEFORE realloc.
    % =====================================================================
    atRiskTaskIDs = identifyAtRiskTasks(tasks, events, degEvents);
    nAtRisk = numel(atRiskTaskIDs);

    if nAtRisk > 0
        salvagedTasks = atRiskTaskIDs(strcmp({tasks(atRiskTaskIDs).status}, 'complete'));
    else
        salvagedTasks = [];
    end
    nRealloc = numel(salvagedTasks);

    % =====================================================================
    % R_time (Eq. 6): recovery to a new throughput equilibrium.
    % Denominator is the remaining mission horizon (shared across methods
    % on a CRN-paired instance). It is NOT min(tEnd, max completeTime).
    % =====================================================================
    tSS = detectThroughputEquilibrium(tasks, events, cfg, tEnd, tLastDeg);
    T_recover = min(deltaT, max(0, tSS - tStart));
    pm.R_time = max(0, 1 - (T_recover / deltaT));

    % =====================================================================
    % R_task (Eq. 5): completion value plus reallocation gain.
    % lambda_max is not specified numerically in the paper; keep a bounded
    % value-weighted ratio with the corrected N_realloc / nAtRisk.
    % =====================================================================
    taskValues = [tasks.priority];
    totalTaskValue = sum(taskValues);
    completedValues = 0;
    if any(completedMask)
        completedValues = sum([tasks(completedMask).priority]);
    end
    maxTheoreticalValue = totalTaskValue + gamma * max(1, nAtRisk);
    achievedValue = completedValues + gamma * nRealloc;
    pm.R_task = min(1.0, achievedValue / maxTheoreticalValue);

    % =====================================================================
    % Salvage fraction of the true at-risk set (do-nothing counterfactual
    % on TASKS, not swarm throughput Theta).
    % =====================================================================
    if nAtRisk > 0
        pm.throughputRecovery = nRealloc / nAtRisk;
    else
        pm.throughputRecovery = 1.0;
    end

    pm.CRI = alpha * pm.R_task + (1 - alpha) * pm.R_time;
    pm.nAtRisk = nAtRisk;
    pm.nSalvaged = nRealloc;
    pm.T_recover = T_recover;
    pm.deltaT = deltaT;
end

function atRiskTaskIDs = identifyAtRiskTasks(tasks, events, degEvents)
% Replay assignment updates in log order. When a degradation event is
% reached, the current assignment is the pre-reallocation state.
    nT = numel(tasks);
    assigned = zeros(1, nT);
    completeTime = nan(1, nT);
    for j = 1:nT
        completeTime(j) = tasks(j).completeTime;
    end

    atRiskTaskIDs = [];
    nE = numel(events);
    nDeg = numel(degEvents);
    if nE == 0 || nDeg == 0
        return;
    end

    for e = 1:nE
        ev = events(e);
        if strcmp(ev.trigger, 'degradation')
            uFail = ev.newUAV;
            capLost = ev.reason;
            tDeg = ev.time;
            for j = 1:nT
                if assigned(j) ~= uFail
                    continue;
                end
                if ~isnan(completeTime(j)) && completeTime(j) < tDeg
                    continue;
                end
                if taskRequiresCap(tasks(j).requiredCap, capLost)
                    atRiskTaskIDs(end+1) = j; %#ok<AGROW>
                end
            end
        elseif ev.taskIdx > 0
            assigned(ev.taskIdx) = ev.newUAV;
        end
    end
    atRiskTaskIDs = unique(atRiskTaskIDs);
end

function tf = taskRequiresCap(requiredCap, capLost)
    if iscell(requiredCap)
        tf = any(strcmp(requiredCap, capLost));
    elseif ischar(requiredCap) || isstring(requiredCap)
        tf = strcmp(requiredCap, capLost);
    else
        tf = false;
    end
end

function tSS = detectThroughputEquilibrium(tasks, events, cfg, tEnd, tLastDeg)
% tSS = first time at/after the last degradation at which the swarm has
% left the overload regime (max |Q_i| <= N_Mi) and stays clear for a
% short persistence window. This is the operationalization of Zeng et al.
% Eq. 6 "recovery duration from performance drop to steady-state
% equilibrium" for discrete-time sims that reallocate on the failure tick.
%
% If overload never clears, tSS = tEnd (failed to recover).

    nT = numel(tasks);
    nU = numel(cfg.uav);
    NMi = nT;
    if isfield(cfg, 'bdtr') && isfield(cfg.bdtr, 'nominalCapacity')
        NMi = cfg.bdtr.nominalCapacity;
    end
    dt = 1;
    if isfield(cfg, 'sim') && isfield(cfg.sim, 'dt')
        dt = cfg.sim.dt;
    end
    persist = max(dt, 5);

    completeTime = nan(1, nT);
    deadline = inf(1, nT);
    for j = 1:nT
        completeTime(j) = tasks(j).completeTime;
        deadline(j) = tasks(j).deadline;
    end

    nE = numel(events);
    evTime = zeros(1, nE);
    evTask = zeros(1, nE);
    evNew = zeros(1, nE);
    evTrig = cell(1, nE);
    for e = 1:nE
        evTime(e) = events(e).time;
        evTask(e) = events(e).taskIdx;
        evNew(e) = events(e).newUAV;
        evTrig{e} = events(e).trigger;
    end

    assigned = zeros(1, nT);
    evIdx = 1;
    tSS = tEnd;
    clearRun = 0;

    for t = 0:dt:tEnd
        newlyAtRisk = [];
        while evIdx <= nE && evTime(evIdx) <= t
            if strcmp(evTrig{evIdx}, 'degradation')
                uFail = evNew(evIdx);
                % cap is events(evIdx).reason; need it for at-risk snapshot
                capLost = events(evIdx).reason;
                for j = 1:nT
                    if assigned(j) == uFail && taskRequiresCap(tasks(j).requiredCap, capLost)
                        if isnan(completeTime(j)) || completeTime(j) >= t
                            newlyAtRisk(end+1) = j; %#ok<AGROW>
                        end
                    end
                end
            elseif evTask(evIdx) > 0
                assigned(evTask(evIdx)) = evNew(evIdx);
            end
            evIdx = evIdx + 1;
        end

        % Methods that drop an at-risk task log no assignment event
        % (BDTR empty U_cand, Hungarian dummy). Clear those queues.
        if ~isempty(newlyAtRisk)
            reassigned = false(1, nT);
            for e = 1:nE
                if evTime(e) == t && evTask(e) > 0 && evNew(e) > 0
                    reassigned(evTask(e)) = true;
                end
            end
            for k = 1:numel(newlyAtRisk)
                j = newlyAtRisk(k);
                if ~reassigned(j)
                    assigned(j) = 0;
                end
            end
        end

        for j = 1:nT
            if ~isnan(completeTime(j)) && completeTime(j) <= t
                assigned(j) = 0;
            elseif deadline(j) <= t && (isnan(completeTime(j)) || completeTime(j) > t)
                assigned(j) = 0;
            end
        end

        if t < tLastDeg
            continue;
        end

        Qlen = zeros(1, nU);
        for j = 1:nT
            i = assigned(j);
            if i >= 1 && i <= nU
                Qlen(i) = Qlen(i) + 1;
            end
        end
        if isempty(Qlen) || max(Qlen) <= NMi
            clearRun = clearRun + dt;
            if clearRun >= persist
                tSS = t - persist + dt;
                if tSS < tLastDeg
                    tSS = tLastDeg;
                end
                return;
            end
        else
            clearRun = 0;
        end
    end
end
