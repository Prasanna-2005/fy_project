function renderFrame(rs, uavs, tasks, t, events)
% RENDERFRAME  Update one animation frame with Ground Control Station layout:
%   - Left Panel (ax3D): 3D Tactical Flight Arena with clean status markers,
%     active task rays, and dynamic flight telemetry.
%   - Right Panel (axDash): Telemetry Dashboard (Fleet Status Cards,
%     Task Status & Active Tasks Board, Live Event Feed).

if nargin < 5
    events = [];
end

ax3D   = rs.ax3D;
axDash = rs.axDash;
scene  = rs.scene;
nUAV   = numel(uavs);
nT     = numel(tasks);

% ---- 1. Update UAV Platform Positions in UAV Toolbox (ENU -> NED) ----
for i = 1:nUAV
    nedPos = enu2ned(uavs(i).position);
    state16 = [nedPos, 0 0 0, 0 0 0, 1 0 0 0, 0 0 0];
    move(rs.platforms{i}, state16);
end

advance(scene);
show3D(scene, 'Parent', ax3D, 'FastUpdate', 1);

% Re-apply fixed limits on 3D axes
maxX = max(100, max(arrayfun(@(k) k.location(1), tasks)) + 10);
maxY = max(100, max(arrayfun(@(k) k.location(2), tasks)) + 10);
maxZ = max(35, max(arrayfun(@(k) k.location(3), tasks)) + 10);
xlim(ax3D, [-5 maxX]);
ylim(ax3D, [-5 maxY]);
zlim(ax3D, [ 0 maxZ]);
axis(ax3D, 'manual');

% =========================================================================
% LEFT PANEL: 3D TACTICAL FLIGHT ARENA
% =========================================================================
delete(findobj(ax3D, 'Tag', 'overlay'));
hold(ax3D, 'on');

% Launch base pad anchor
scatter3(ax3D, 15, 15, 0.1, 220, [0.40 0.44 0.52], 's', ...
    'LineWidth', 1.2, 'Tag', 'overlay');
text(ax3D, 15, 15, 0.8, 'LAUNCH BASE', ...
    'Color', [0.60 0.65 0.75], 'FontSize', 6.5, 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', 'Tag', 'overlay');

% Active Task Rays (UAV -> Assigned Target Waypoint)
for i = 1:nUAV
    j = uavs(i).assignedTask;
    if j > 0 && j <= nT
        p = uavs(i).position;
        q = tasks(j).location;
        plot3(ax3D, [p(1) q(1)], [p(2) q(2)], [p(3) q(3)], '--', ...
            'Color', [rs.uavColors(i,:) 0.80], 'LineWidth', 1.6, 'Tag', 'overlay');
        scatter3(ax3D, q(1), q(2), q(3), 150, rs.uavColors(i,:), ...
            'LineWidth', 1.5, 'Tag', 'overlay');
    end
end

% Waypoints: Visual markers & status cues
for j = 1:nT
    q   = tasks(j).location;
    st  = tasks(j).status;
    reason = tasks(j).atriskReason;

    isPreempted  = strcmp(st, 'atrisk') && strcmp(reason, 'Displaced');
    isExecOnSite = strcmp(st, 'assigned') && ~isnan(tasks(j).arrivalTime);
    isEnRoute    = strcmp(st, 'assigned') && isnan(tasks(j).arrivalTime);
    isComplete   = strcmp(st, 'complete');
    isFailed     = strcmp(st, 'failed');

    % Color coding
    if isComplete
        col = rs.taskColors.complete;
    elseif isExecOnSite
        col = rs.taskColors.executing;
    elseif isEnRoute
        col = rs.taskColors.assigned;
    elseif isPreempted
        col = rs.taskColors.preempted;
    elseif strcmp(st, 'atrisk')
        col = rs.taskColors.atrisk;
    elseif isFailed
        col = rs.taskColors.failed;
    else
        col = rs.taskColors.unassigned;
    end

    % Dotted drop stem for 3D depth perception
    plot3(ax3D, [q(1) q(1)], [q(2) q(2)], [0 q(3)], ':', ...
        'Color', [0.35 0.38 0.45 0.35], 'LineWidth', 0.6, 'Tag', 'overlay');

    % Waypoint marker
    if isPreempted
        scatter3(ax3D, q(1), q(2), q(3), 110, col, 'h', 'filled', ...
            'MarkerEdgeColor', 'w', 'LineWidth', 1.0, 'Tag', 'overlay');
    elseif isComplete
        scatter3(ax3D, q(1), q(2), q(3), 60, col, 'o', 'filled', ...
            'MarkerEdgeColor', 'w', 'LineWidth', 0.6, 'Tag', 'overlay');
    elseif isExecOnSite || isEnRoute
        scatter3(ax3D, q(1), q(2), q(3), 90, col, 'd', 'filled', ...
            'MarkerEdgeColor', 'w', 'LineWidth', 0.9, 'Tag', 'overlay');
    else
        scatter3(ax3D, q(1), q(2), q(3), 45, col, 's', 'filled', ...
            'MarkerEdgeColor', 'none', 'Tag', 'overlay');
    end

    % Display text labels selectively (active tasks or at-risk tasks) to prevent clutter
    if isExecOnSite
        dt_exec = min(tasks(j).execTime, max(0, t - tasks(j).arrivalTime));
        pct = round(100 * dt_exec / tasks(j).execTime);
        text(ax3D, q(1), q(2), q(3) + 2.2, sprintf('T%d [%d%%]', j, pct), ...
            'Color', rs.taskColors.executing, 'FontSize', 6.8, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'Tag', 'overlay');
    elseif isEnRoute
        text(ax3D, q(1), q(2), q(3) + 2.2, sprintf('T%d [UAV%d]', j, tasks(j).assignedUAV), ...
            'Color', rs.taskColors.assigned, 'FontSize', 6.5, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'Tag', 'overlay');
    elseif isPreempted || strcmp(st, 'atrisk')
        text(ax3D, q(1), q(2), q(3) + 2.2, sprintf('T%d [!]', j), ...
            'Color', col, 'FontSize', 7.0, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'Tag', 'overlay');
    end
end

% UAV Platform Labels
for i = 1:nUAV
    p = uavs(i).position;
    text(ax3D, p(1), p(2), p(3) + 3.5, ...
        sprintf('%s', uavs(i).name), ...
        'Color', rs.uavColors(i,:), 'FontSize', 8.2, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'Tag', 'overlay');
end

completedCount = sum(strcmp({tasks.status}, 'complete'));
activeCount    = sum(strcmp({tasks.status}, 'assigned'));
preemptedCount = sum(strcmp({tasks.status}, 'atrisk'));
failedCount    = sum(strcmp({tasks.status}, 'failed'));

title(ax3D, sprintf('TACTICAL ARENA   |   t = %3d s   |   Done: %d/%d   Active: %d   Preempted: %d   Failed: %d', ...
    t, completedCount, nT, activeCount, preemptedCount, failedCount), ...
    'Color', [0.95 0.95 0.95], 'FontSize', 10.0, 'FontWeight', 'bold');

hold(ax3D, 'off');

% =========================================================================
% RIGHT PANEL: MISSION OPERATIONS DASHBOARD (axDash)
% =========================================================================
delete(findobj(axDash, 'Tag', 'dash_overlay'));
hold(axDash, 'on');

% Header Card: Y = 91..99
rectangle(axDash, 'Position', [2, 91, 96, 8], 'Curvature', 0.15, ...
    'FaceColor', [0.08 0.10 0.15], 'EdgeColor', [0.20 0.25 0.35], 'Tag', 'dash_overlay');

text(axDash, 5, 96, sprintf('STRATEGY: %s', upper(rs.strategy)), ...
    'Color', [0.00 0.85 1.00], 'FontSize', 10.0, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
text(axDash, 5, 93, sprintf('Mission Clock: %3d s  |  Completed: %d/%d (%.1f%%)  |  Failed: %d', ...
    t, completedCount, nT, (completedCount/nT)*100, failedCount), ...
    'Color', [0.85 0.88 0.92], 'FontSize', 7.5, 'Tag', 'dash_overlay');

% -------------------------------------------------------------------------
% Card 1: FLEET TELEMETRY & CAPABILITIES (Y = 62..89)
% -------------------------------------------------------------------------
rectangle(axDash, 'Position', [2, 62, 96, 27], 'Curvature', 0.10, ...
    'FaceColor', [0.07 0.09 0.13], 'EdgeColor', [0.18 0.22 0.30], 'Tag', 'dash_overlay');

text(axDash, 5, 86.5, sprintf('FLEET TELEMETRY (%d UAVs)', nUAV), ...
    'Color', [0.95 0.78 0.15], 'FontSize', 8.5, 'FontWeight', 'bold', 'Tag', 'dash_overlay');

yUAV = linspace(82.5, 65.0, nUAV);
for i = 1:nUAV
    yPos = yUAV(i);
    scatter(axDash, 5.5, yPos + 0.8, 30, rs.uavColors(i,:), 'filled', 'Tag', 'dash_overlay');

    j = uavs(i).assignedTask;
    qLen = numel(uavs(i).queue);
    if j > 0 && j <= nT
        if ~isnan(tasks(j).arrivalTime)
            stStr = sprintf('WORKING T%d (Q:%d)', j, qLen);
            stCol = rs.taskColors.executing;
        else
            stStr = sprintf('FLYING -> T%d (Q:%d)', j, qLen);
            stCol = [0.95 0.95 0.95];
        end
    else
        stStr = sprintf('IDLE (Q:%d)', qLen);
        stCol = [0.55 0.58 0.65];
    end

    % Capability & degradation detection
    currCaps = uavs(i).capabilities;
    if isfield(rs, 'cfg') && i <= numel(rs.cfg.uav)
        initCaps = rs.cfg.uav(i).capabilities;
        lostCaps = setdiff(initCaps, currCaps);
    else
        lostCaps = {};
    end

    if ~isempty(lostCaps)
        capStr = [strjoin(currCaps, '+') sprintf(' [%s: LOST!]', strjoin(lostCaps, ','))];
        capCol = [1.00 0.30 0.25];
    else
        capStr = strjoin(currCaps, '+');
        capCol = [0.65 0.70 0.78];
    end

    text(axDash, 9, yPos + 0.8, sprintf('%s: %s', uavs(i).name, stStr), ...
        'Color', stCol, 'FontSize', 7.0, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
    text(axDash, 58, yPos + 0.8, capStr, ...
        'Color', capCol, 'FontSize', 6.5, 'Tag', 'dash_overlay');
end

% -------------------------------------------------------------------------
% Card 2: MISSION TASK BOARD & ACTIVE ROSTER (Y = 24..60)
% -------------------------------------------------------------------------
rectangle(axDash, 'Position', [2, 23, 96, 38], 'Curvature', 0.10, ...
    'FaceColor', [0.07 0.09 0.13], 'EdgeColor', [0.18 0.22 0.30], 'Tag', 'dash_overlay');

text(axDash, 5, 58.5, sprintf('TASK BOARD (%d Waypoints)', nT), ...
    'Color', [0.95 0.78 0.15], 'FontSize', 8.5, 'FontWeight', 'bold', 'Tag', 'dash_overlay');

% Column Headers: TASK, REQ, PRI, DDL, STATUS & PROGRESS
text(axDash, 5,  55.0, 'TASK', 'Color', [0.55 0.60 0.70], 'FontSize', 6.2, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
text(axDash, 15, 55.0, 'REQ',  'Color', [0.55 0.60 0.70], 'FontSize', 6.2, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
text(axDash, 30, 55.0, 'PRI',  'Color', [0.55 0.60 0.70], 'FontSize', 6.2, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
text(axDash, 44, 55.0, 'DDL',  'Color', [0.55 0.60 0.70], 'FontSize', 6.2, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
text(axDash, 55, 55.0, 'STATUS & PROGRESS', 'Color', [0.55 0.60 0.70], 'FontSize', 6.2, 'FontWeight', 'bold', 'Tag', 'dash_overlay');

yTask = linspace(51.8, 25.0, nT);
for j = 1:nT
    yPos = yTask(j);
    st  = tasks(j).status;
    pri = tasks(j).priority;
    req = strjoin(tasks(j).requiredCap, '+');
    reason = tasks(j).atriskReason;

    switch pri
        case 3, priStr = 'P3-HI';  priCol = rs.priorityColors.p3;
        case 2, priStr = 'P2-MED'; priCol = rs.priorityColors.p2;
        otherwise, priStr = 'P1-LOW'; priCol = rs.priorityColors.p1;
    end

    if strcmp(st, 'complete')
        statusText = sprintf('DONE (t=%ds)', round(tasks(j).completeTime));
        col = rs.taskColors.complete;
    elseif strcmp(st, 'assigned')
        if ~isnan(tasks(j).arrivalTime)
            dt_exec = min(tasks(j).execTime, max(0, t - tasks(j).arrivalTime));
            pct = round(100 * dt_exec / tasks(j).execTime);
            statusText = sprintf('WORK UAV%d (%d%%)', tasks(j).assignedUAV, pct);
            col = rs.taskColors.executing;
        else
            statusText = sprintf('EN ROUTE (UAV%d)', tasks(j).assignedUAV);
            col = rs.taskColors.assigned;
        end
    elseif strcmp(st, 'atrisk')
        if strcmp(reason, 'Displaced')
            statusText = 'PREEMPTED / DISPLACED!';
            col = rs.taskColors.preempted;
        else
            statusText = sprintf('AT-RISK (%s)', reason);
            col = rs.taskColors.atrisk;
        end
    elseif strcmp(st, 'failed')
        statusText = 'FAILED (Deadline Expired)';
        col = rs.taskColors.failed;
    else
        statusText = 'QUEUED';
        col = rs.taskColors.unassigned;
    end

    text(axDash, 5,  yPos, sprintf('T%-2d', j), 'Color', [0.90 0.92 0.96], 'FontSize', 6.5, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
    text(axDash, 15, yPos, req, 'Color', [0.70 0.75 0.82], 'FontSize', 6.2, 'Tag', 'dash_overlay');
    text(axDash, 30, yPos, priStr, 'Color', priCol, 'FontSize', 6.2, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
    text(axDash, 44, yPos, sprintf('%ds', tasks(j).deadline), 'Color', [0.80 0.85 0.90], 'FontSize', 6.2, 'Tag', 'dash_overlay');
    text(axDash, 55, yPos, statusText, 'Color', col, 'FontSize', 6.5, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
end

% -------------------------------------------------------------------------
% Card 3: LIVE MISSION EVENT FEED (Y = 2..22)
% -------------------------------------------------------------------------
rectangle(axDash, 'Position', [2, 2, 96, 20], 'Curvature', 0.10, ...
    'FaceColor', [0.07 0.09 0.13], 'EdgeColor', [0.18 0.22 0.30], 'Tag', 'dash_overlay');

text(axDash, 5, 19.5, 'LIVE MISSION EVENT FEED', ...
    'Color', [0.95 0.78 0.15], 'FontSize', 8.5, 'FontWeight', 'bold', 'Tag', 'dash_overlay');

eventLines = {};
if ~isempty(events)
    pastEvents = events([events.time] <= t);
    if ~isempty(pastEvents)
        if numel(pastEvents) > 4
            dispEvents = pastEvents(end-3:end);
        else
            dispEvents = pastEvents;
        end

        for e = 1:numel(dispEvents)
            ev = dispEvents(e);
            if strcmp(ev.trigger, 'degradation')
                eventLines{end+1} = sprintf('[t=%2ds] ATTACK: %s lost on UAV%d', ...
                    round(ev.time), ev.reason, ev.newUAV); %#ok<AGROW>
            elseif strcmp(ev.trigger, 'initial')
                eventLines{end+1} = sprintf('[t=%2ds] INIT: T%d -> UAV%d (%s)', ...
                    round(ev.time), ev.taskIdx, ev.newUAV, ev.reason); %#ok<AGROW>
            else
                eventLines{end+1} = sprintf('[t=%2ds] REALLOC: T%d -> UAV%d (%s)', ...
                    round(ev.time), ev.taskIdx, ev.newUAV, ev.reason); %#ok<AGROW>
            end
        end
    end
end

yEv = [15.5, 12.0, 8.5, 5.0];
for e = 1:numel(eventLines)
    if e <= numel(yEv)
        text(axDash, 5, yEv(e), eventLines{e}, ...
            'Color', [0.80 0.85 0.92], 'FontSize', 6.5, 'Tag', 'dash_overlay');
    end
end

hold(axDash, 'off');
drawnow;
end

function nedPos = enu2ned(enuPos)
nedPos = [enuPos(2), enuPos(1), -enuPos(3)];
end
