function renderFrame(rs, uavs, tasks, t, events)
% RENDERFRAME  Update one animation frame with Ground Control Station layout:
%   - Left Panel (ax3D): 3D Tactical Flight Arena with deadline display,
%     sub-waypoint progress/queued telemetry, and dynamic status coloring.
%   - Right Panel (axDash): Telemetry Dashboard (Fleet Cards, Task Board, Event Feed).

if nargin < 5
    events = [];
end

ax3D   = rs.ax3D;
axDash = rs.axDash;
scene  = rs.scene;

% ---- 1. Update UAV Platform Positions in UAV Toolbox (ENU -> NED) ----
for i = 1:numel(uavs)
    nedPos = enu2ned(uavs(i).position);
    state16 = [nedPos, 0 0 0, 0 0 0, 1 0 0 0, 0 0 0];
    move(rs.platforms{i}, state16);
end

advance(scene);
show3D(scene, 'Parent', ax3D, 'FastUpdate', 1);

% Re-apply fixed limits on 3D axes
xlim(ax3D, [-5 105]);
ylim(ax3D, [-5 105]);
zlim(ax3D, [ 0  36]);
axis(ax3D, 'manual');

% =========================================================================
% LEFT PANEL: 3D TACTICAL FLIGHT ARENA
% =========================================================================
delete(findobj(ax3D, 'Tag', 'overlay'));
hold(ax3D, 'on');

% Launch base pad anchor
scatter3(ax3D, 15, 15, 0.1, 240, [0.40 0.44 0.52], 's', ...
    'LineWidth', 1.2, 'Tag', 'overlay');
text(ax3D, 15, 15, 0.8, 'LAUNCH BASE', ...
    'Color', [0.60 0.65 0.75], 'FontSize', 6.5, 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', 'Tag', 'overlay');

% Assignment Vectors (UAV -> Target Waypoint Rays)
for i = 1:numel(uavs)
    j = uavs(i).assignedTask;
    if j > 0 && j <= numel(tasks)
        p = uavs(i).position;
        q = tasks(j).location;
        % Dynamic flight ray
        plot3(ax3D, [p(1) q(1)], [p(2) q(2)], [p(3) q(3)], '--', ...
            'Color', [rs.uavColors(i,:) 0.75], 'LineWidth', 1.6, 'Tag', 'overlay');
        % Target indicator ring
        scatter3(ax3D, q(1), q(2), q(3), 160, rs.uavColors(i,:), ...
            'LineWidth', 1.5, 'Tag', 'overlay');
    end
end

% Waypoints: Visual color cues + Deadline + Sub-waypoint Progress / Queued Status
for j = 1:numel(tasks)
    q   = tasks(j).location;
    st  = tasks(j).status;
    pri = tasks(j).priority;
    reason = tasks(j).atriskReason;

    isPreempted  = strcmp(st, 'atrisk') && strcmp(reason, 'Displaced');
    isExecOnSite = strcmp(st, 'assigned') && ~isnan(tasks(j).arrivalTime);
    isEnRoute    = strcmp(st, 'assigned') && isnan(tasks(j).arrivalTime);
    isComplete   = strcmp(st, 'complete');
    isFailed     = strcmp(st, 'failed');

    % Determine marker color & sub-label text
    if isComplete
        col = rs.taskColors.complete;
        subStr = sprintf('[DONE @ %ds]', round(tasks(j).completeTime));
        subCol = rs.taskColors.complete;
    elseif isExecOnSite
        col = rs.taskColors.executing;
        dt_exec = min(tasks(j).execTime, max(0, t - tasks(j).arrivalTime));
        pct = round(100 * dt_exec / tasks(j).execTime);
        subStr = sprintf('[WORKING %d%% (%ds/%ds)]', pct, dt_exec, tasks(j).execTime);
        subCol = rs.taskColors.executing;
    elseif isEnRoute
        col = rs.taskColors.assigned;  % picked / en route
        subStr = sprintf('[EN ROUTE: UAV%d]', tasks(j).assignedUAV);
        subCol = rs.taskColors.assigned;
    elseif isPreempted
        col = rs.taskColors.preempted;
        subStr = '[PREEMPTED / DISPLACED]';
        subCol = rs.taskColors.preempted;
    elseif strcmp(st, 'atrisk')
        col = rs.taskColors.atrisk;
        subStr = sprintf('[AT-RISK: %s]', reason);
        subCol = rs.taskColors.atrisk;
    elseif isFailed
        col = rs.taskColors.failed;
        subStr = '[DEADLINE EXPIRED]';
        subCol = rs.taskColors.failed;
    else
        col = rs.taskColors.unassigned;  % queued / unassigned (gray)
        subStr = '[QUEUED]';
        subCol = [0.65 0.70 0.78];
    end

    % Dotted drop stem for 3D depth perception
    plot3(ax3D, [q(1) q(1)], [q(2) q(2)], [0 q(3)], ':', ...
        'Color', [0.35 0.38 0.45 0.45], 'LineWidth', 0.8, 'Tag', 'overlay');

    % Waypoint marker
    if isPreempted
        scatter3(ax3D, q(1), q(2), q(3), 130, col, 'h', 'filled', ...
            'MarkerEdgeColor', 'w', 'LineWidth', 1.2, 'Tag', 'overlay');
        scatter3(ax3D, q(1), q(2), q(3), 260, col, 'LineWidth', 1.5, 'Tag', 'overlay');
    elseif isComplete
        scatter3(ax3D, q(1), q(2), q(3), 85, col, 'o', 'filled', ...
            'MarkerEdgeColor', 'w', 'LineWidth', 0.8, 'Tag', 'overlay');
    else
        scatter3(ax3D, q(1), q(2), q(3), 85, col, 'd', 'filled', ...
            'MarkerEdgeColor', 'w', 'LineWidth', 0.8, 'Tag', 'overlay');
    end

    % 1) Header label beside waypoint: T<id> [P<pri> | ddl:<ddl>s]
    text(ax3D, q(1) + 2.0, q(2), q(3) + 1.2, ...
        sprintf('T%d [P%d | ddl:%ds]', j, pri, tasks(j).deadline), ...
        'Color', [0.95 0.95 0.95], 'FontSize', 7.2, 'FontWeight', 'bold', ...
        'Tag', 'overlay');

    % 3) Under waypoint: [QUEUED] / [EN ROUTE] / [WORKING %] / [PREEMPTED]
    text(ax3D, q(1), q(2), q(3) - 3.2, ...
        subStr, ...
        'Color', subCol, 'FontSize', 6.6, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'Tag', 'overlay');
end

% UAV Platform Labels: Crisp single-line identifiers
for i = 1:numel(uavs)
    p = uavs(i).position;
    text(ax3D, p(1), p(2), p(3) + 3.8, ...
        sprintf('%s', uavs(i).name), ...
        'Color', rs.uavColors(i,:), 'FontSize', 8.5, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'Tag', 'overlay');
end

completedCount = sum(strcmp({tasks.status}, 'complete'));
activeCount    = sum(strcmp({tasks.status}, 'assigned'));
preemptedCount = sum(strcmp({tasks.status}, 'atrisk'));
failedCount    = sum(strcmp({tasks.status}, 'failed'));

title(ax3D, sprintf('TACTICAL ARENA (100x100m)   |   t = %3d s   |   Done: %d/%d   Active: %d   Preempted: %d', ...
    t, completedCount, numel(tasks), activeCount, preemptedCount), ...
    'Color', [0.95 0.95 0.95], 'FontSize', 10.5, 'FontWeight', 'bold');

hold(ax3D, 'off');

% =========================================================================
% RIGHT PANEL: MISSION OPERATIONS DASHBOARD (axDash)
% =========================================================================
delete(findobj(axDash, 'Tag', 'dash_overlay'));
hold(axDash, 'on');

% Background Card Containers
% Header Card: Y = 90..99
rectangle(axDash, 'Position', [2, 90, 96, 9], 'Curvature', 0.15, ...
    'FaceColor', [0.08 0.10 0.15], 'EdgeColor', [0.20 0.25 0.35], 'Tag', 'dash_overlay');

text(axDash, 5, 96, sprintf('STRATEGY: %s', upper(rs.strategy)), ...
    'Color', [0.00 0.85 1.00], 'FontSize', 10.5, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
text(axDash, 5, 92.5, sprintf('Mission Clock: %3d s  |  Completed: %d/%d  |  Failed: %d', ...
    t, completedCount, numel(tasks), failedCount), ...
    'Color', [0.85 0.88 0.92], 'FontSize', 8, 'Tag', 'dash_overlay');

% -------------------------------------------------------------------------
% Card 1: FLEET STATUS & DUAL DEGRADATION TELEMETRY (4 UAVs) (Y = 65..88)
% -------------------------------------------------------------------------
rectangle(axDash, 'Position', [2, 65, 96, 23], 'Curvature', 0.10, ...
    'FaceColor', [0.07 0.09 0.13], 'EdgeColor', [0.18 0.22 0.30], 'Tag', 'dash_overlay');

text(axDash, 5, 85.5, 'FLEET TELEMETRY & CAPABILITIES (4 UAVs)', ...
    'Color', [0.95 0.78 0.15], 'FontSize', 9, 'FontWeight', 'bold', 'Tag', 'dash_overlay');

yUAV = [80.5, 75.5, 70.5, 65.5];
for i = 1:numel(uavs)
    yPos = yUAV(i);
    % Color indicator dot
    scatter(axDash, 5.5, yPos + 0.8, 35, rs.uavColors(i,:), 'filled', 'Tag', 'dash_overlay');

    % UAV state & destination
    j = uavs(i).assignedTask;
    if j > 0 && j <= numel(tasks)
        if ~isnan(tasks(j).arrivalTime)
            stStr = sprintf('WORKING on T%d', j);
            stCol = rs.taskColors.executing;
        else
            stStr = sprintf('FLYING -> T%d', j);
            stCol = [0.95 0.95 0.95];
        end
    else
        stStr = 'IDLE';
        stCol = [0.55 0.58 0.65];
    end

    % Payloads & degradation status (Dual degradation: UAV1 Thermal, UAV3 LiDAR)
    capList = uavs(i).capabilities;
    if i == 1 && ~ismember('Thermal', capList) && t >= 20
        capStr = 'Camera, [Thermal: LOST!]';
        capCol = [1.00 0.30 0.25];
    elseif i == 3 && ~ismember('LiDAR', capList) && t >= 35
        capStr = 'Camera, [LiDAR: LOST!]';
        capCol = [1.00 0.30 0.25];
    else
        capStr = strjoin(capList, '+');
        capCol = [0.65 0.70 0.78];
    end

    text(axDash, 9, yPos + 0.8, sprintf('%s: %s', uavs(i).name, stStr), ...
        'Color', stCol, 'FontSize', 7.5, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
    text(axDash, 56, yPos + 0.8, capStr, ...
        'Color', capCol, 'FontSize', 6.8, 'Tag', 'dash_overlay');
end

% -------------------------------------------------------------------------
% Card 2: TASK BOARD (10 Tasks with Deadline Column) (Y = 26..63)
% -------------------------------------------------------------------------
rectangle(axDash, 'Position', [2, 26, 96, 37], 'Curvature', 0.10, ...
    'FaceColor', [0.07 0.09 0.13], 'EdgeColor', [0.18 0.22 0.30], 'Tag', 'dash_overlay');

text(axDash, 5, 60.8, 'TASK BOARD (10 Waypoints)', ...
    'Color', [0.95 0.78 0.15], 'FontSize', 9, 'FontWeight', 'bold', 'Tag', 'dash_overlay');

% Column Headers: TASK, PAYLOAD, PRI, DDL, STATUS & PROGRESS
text(axDash, 5, 57.5, 'TASK', 'Color', [0.55 0.60 0.70], 'FontSize', 6.5, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
text(axDash, 15, 57.5, 'REQ', 'Color', [0.55 0.60 0.70], 'FontSize', 6.5, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
text(axDash, 31, 57.5, 'PRI', 'Color', [0.55 0.60 0.70], 'FontSize', 6.5, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
text(axDash, 45, 57.5, 'DDL', 'Color', [0.55 0.60 0.70], 'FontSize', 6.5, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
text(axDash, 55, 57.5, 'STATUS & PROGRESS', 'Color', [0.55 0.60 0.70], 'FontSize', 6.5, 'FontWeight', 'bold', 'Tag', 'dash_overlay');

yTask = linspace(54.2, 28.5, 10);
for j = 1:numel(tasks)
    yPos = yTask(j);
    st  = tasks(j).status;
    pri = tasks(j).priority;
    req = strjoin(tasks(j).requiredCap, '+');
    reason = tasks(j).atriskReason;

    % Priority badge & color
    switch pri
        case 3, priStr = 'P3-HI';  priCol = rs.priorityColors.p3;
        case 2, priStr = 'P2-MED'; priCol = rs.priorityColors.p2;
        otherwise, priStr = 'P1-LOW'; priCol = rs.priorityColors.p1;
    end

    % Status text & color
    if strcmp(st, 'complete')
        statusText = sprintf('DONE (t=%ds)', round(tasks(j).completeTime));
        col = rs.taskColors.complete;
    elseif strcmp(st, 'assigned')
        if ~isnan(tasks(j).arrivalTime)
            dt_exec = min(tasks(j).execTime, max(0, t - tasks(j).arrivalTime));
            pct = round(100 * dt_exec / tasks(j).execTime);
            statusText = sprintf('WORKING UAV%d (%d%%)', tasks(j).assignedUAV, pct);
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

    text(axDash, 5, yPos, sprintf('T%-2d', j), ...
        'Color', [0.90 0.92 0.96], 'FontSize', 6.8, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
    text(axDash, 15, yPos, req, ...
        'Color', [0.70 0.75 0.82], 'FontSize', 6.5, 'Tag', 'dash_overlay');
    text(axDash, 31, yPos, priStr, ...
        'Color', priCol, 'FontSize', 6.5, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
    text(axDash, 45, yPos, sprintf('%ds', tasks(j).deadline), ...
        'Color', [0.80 0.85 0.90], 'FontSize', 6.5, 'Tag', 'dash_overlay');
    text(axDash, 55, yPos, statusText, ...
        'Color', col, 'FontSize', 6.8, 'FontWeight', 'bold', 'Tag', 'dash_overlay');
end

% -------------------------------------------------------------------------
% Card 3: LIVE MISSION EVENT FEED (Y = 2..24)
% -------------------------------------------------------------------------
rectangle(axDash, 'Position', [2, 2, 96, 22], 'Curvature', 0.10, ...
    'FaceColor', [0.07 0.09 0.13], 'EdgeColor', [0.18 0.22 0.30], 'Tag', 'dash_overlay');

text(axDash, 5, 21.5, 'LIVE MISSION EVENT FEED', ...
    'Color', [0.95 0.78 0.15], 'FontSize', 9, 'FontWeight', 'bold', 'Tag', 'dash_overlay');

eventLines = {};
if ~isempty(events)
    pastEvents = events([events.time] <= t);
    if ~isempty(pastEvents)
        recentWindow = 14;
        recentMask = [pastEvents.time] >= max(0, t - recentWindow);
        dispEvents = pastEvents(recentMask);
        if isempty(dispEvents)
            dispEvents = pastEvents(max(1, end-2):end);
        elseif numel(dispEvents) > 4
            dispEvents = dispEvents(end-3:end);
        end

        for e = 1:numel(dispEvents)
            ev = dispEvents(e);
            if strcmp(ev.trigger, 'degradation')
                eventLines{end+1} = sprintf('[t=%2ds] DEGRADE: %s lost on UAV%d', ...
                    ev.time, ev.reason, ev.newUAV); %#ok<AGROW>
            elseif strcmp(ev.trigger, 'reactive-preempt')
                eventLines{end+1} = sprintf('[t=%2ds] PREEMPT: Task%d preempted -> UAV%d', ...
                    ev.time, ev.taskIdx, ev.newUAV); %#ok<AGROW>
            elseif strcmp(ev.trigger, 'reactive')
                eventLines{end+1} = sprintf('[t=%2ds] REALLOC: Task%d -> UAV%d (%s)', ...
                    ev.time, ev.taskIdx, ev.newUAV, ev.reason); %#ok<AGROW>
            elseif strcmp(ev.trigger, 'initial')
                eventLines{end+1} = sprintf('[t=%2ds] INIT ALLOC: Task%d -> UAV%d', ...
                    ev.time, ev.taskIdx, ev.newUAV); %#ok<AGROW>
            else
                eventLines{end+1} = sprintf('[t=%2ds] EVENT: Task%d (%s)', ...
                    ev.time, ev.taskIdx, ev.reason); %#ok<AGROW>
            end
        end
    end
end

if isempty(eventLines)
    if t < 20
        eventLines{1} = sprintf('[t=%3ds] STATUS: Fleet nominal cruising.', t);
        eventLines{2} = 'Sched: UAV1 Thermal loss @ t=20s | UAV3 LiDAR @ t=35s';
    elseif t < 35
        eventLines{1} = sprintf('[t=%3ds] STATUS: UAV1 degraded (Thermal lost).', t);
        eventLines{2} = 'Sched: UAV3 LiDAR loss @ t=35s';
    else
        eventLines{1} = sprintf('[t=%3ds] STATUS: Dual degradation active (UAV1 & UAV3).', t);
        eventLines{2} = 'Fleet reallocations nominal.';
    end
end

yEvents = linspace(17.5, 5.5, max(4, numel(eventLines)));
for e = 1:min(4, numel(eventLines))
    text(axDash, 5, yEvents(e), eventLines{e}, ...
        'Color', [0.88 0.92 0.96], 'FontSize', 7, 'FontName', 'Courier New', ...
        'FontWeight', 'bold', 'Tag', 'dash_overlay');
end

hold(axDash, 'off');

drawnow limitrate;
end

function nedPos = enu2ned(enuPos)
nedPos = [enuPos(2), enuPos(1), -enuPos(3)];
end
