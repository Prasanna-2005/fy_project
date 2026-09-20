function rs = initRender(cfg, strategy)
% INITRENDER  Build Ground Control Station (GCS) Two-Panel Layout:
%   - Left Panel (62% width): 3D Tactical Flight Arena with clean iconography.
%   - Right Panel (31% width): Telemetry & Operations Console (Fleet Cards, Task Board, Event Feed).
%
% This file is the ONLY place that constructs UAV Toolbox objects.
% sim.m passes state data in; nothing flows back.

% ---- UAV Toolbox scenario (simulation time mirrors sim.m) ----
scene = uavScenario( ...
    'UpdateRate', round(1 / cfg.sim.dt), ...
    'StopTime',   cfg.sim.tEnd);

% ---- Colour palette (supports up to 10 UAVs with electric hues) ----
palette = [
    0.00 0.85 1.00;   % UAV1 - Electric Cyan
    1.00 0.48 0.05;   % UAV2 - Bright Orange
    0.72 0.38 1.00;   % UAV3 - Vivid Violet
    1.00 0.18 0.65;   % UAV4 - Hot Pink
    0.20 0.85 0.30;   % UAV5 - Lime Green
    1.00 0.85 0.10;   % UAV6 - Amber Yellow
    0.30 0.60 1.00;   % UAV7 - Sky Blue
    0.95 0.30 0.40;   % UAV8 - Coral Red
    0.10 0.90 0.70;   % UAV9 - Bright Teal
    0.85 0.35 0.90;   % UAV10 - Orchid Purple
];

nUAV = numel(cfg.uav);
uavColors = palette(1:min(nUAV, size(palette, 1)), :);
if nUAV > size(palette, 1)
    extraCols = hsv(nUAV - size(palette, 1));
    uavColors = [uavColors; extraCols];
end

platforms = cell(1, nUAV);
for i = 1:nUAV
    nedPos = enu2ned(cfg.uav(i).position);
    plat = uavPlatform(cfg.uav(i).name, scene, ...
        'ReferenceFrame',  'NED', ...
        'InitialPosition', nedPos);
    % Quadrotor mesh scaled to 5.0m for clean visibility
    updateMesh(plat, 'quadrotor', {5.0}, uavColors(i,:), eul2tform([0 0 pi]));
    platforms{i} = plat;
end

% ---- Open GCS Figure Window ----
fig = figure('Name', ['GCS Tactical Operations - Strategy: ' upper(strategy)], ...
    'Color', [0.05 0.06 0.08], ...
    'NumberTitle', 'off', ...
    'Position', [30 30 1280 720]);

% ---- Left Panel: 3D Tactical Arena (62% width) ----
ax3D = subplot('Position', [0.03, 0.06, 0.62, 0.88]);
setup(scene);
[ax3D, sceneHandles] = show3D(scene, 'Parent', ax3D);

% Arena boundary scaling
maxX = max(100, max(arrayfun(@(t) t.location(1), cfg.task)) + 10);
maxY = max(100, max(arrayfun(@(t) t.location(2), cfg.task)) + 10);
maxZ = max(35, max(arrayfun(@(t) t.location(3), cfg.task)) + 10);

xlim(ax3D, [-5 maxX]);
ylim(ax3D, [-5 maxY]);
zlim(ax3D, [ 0  maxZ]);
axis(ax3D, 'manual');

ax3D.Color           = [0.03 0.04 0.06];
ax3D.GridColor       = [0.25 0.30 0.38];
ax3D.GridAlpha       = 0.35;
ax3D.XColor          = [0.75 0.78 0.84];
ax3D.YColor          = [0.75 0.78 0.84];
ax3D.ZColor          = [0.75 0.78 0.84];
ax3D.FontSize        = 8.5;
ax3D.DataAspectRatio = [1 1 1];

xlabel(ax3D, 'X / East (m)', 'Color', [0.75 0.78 0.84]);
ylabel(ax3D, 'Y / North (m)', 'Color', [0.75 0.78 0.84]);
zlabel(ax3D, 'Z / Altitude (m)', 'Color', [0.75 0.78 0.84]);
view(ax3D, 45, 26);

% ---- Right Panel: 2D Telemetry & Operations Console (31% width) ----
axDash = subplot('Position', [0.67, 0.06, 0.31, 0.88]);
axDash.Color         = [0.05 0.07 0.10];
axDash.XColor        = 'none';
axDash.YColor        = 'none';
xlim(axDash, [0 100]);
ylim(axDash, [0 100]);
axis(axDash, 'manual');

% ---- Task status colors ----
taskColors = struct( ...
    'unassigned', [0.55 0.58 0.65], ...   % Slate Gray (unassigned/queued)
    'assigned',   [1.00 0.78 0.10], ...   % Golden Amber (picked/en route)
    'executing',  [0.20 0.95 0.40], ...   % Bright Lime (working on site)
    'complete',   [0.10 0.85 0.35], ...   % Emerald Green (completed)
    'atrisk',     [0.95 0.50 0.10], ...   % Orange (at risk)
    'preempted',  [1.00 0.25 0.10], ...   % Flaming Red (preempted/displaced)
    'failed',     [0.90 0.15 0.15]);      % Crimson (deadline expired)

priorityColors = struct( ...
    'p3', [1.00 0.22 0.50], ...  % High (P3): Vivid Magenta
    'p2', [1.00 0.75 0.15], ...  % Med (P2): Golden Amber
    'p1', [0.35 0.75 0.95]);     % Low (P1): Cyan

rs = struct( ...
    'scene',          scene,          ...
    'platforms',      {platforms},    ...
    'fig',            fig,            ...
    'ax3D',           ax3D,           ...
    'axDash',         axDash,         ...
    'sceneHandles',   sceneHandles,   ...
    'uavColors',      uavColors,      ...
    'taskColors',     taskColors,     ...
    'priorityColors', priorityColors, ...
    'strategy',       strategy,       ...
    'cfg',            cfg);
end

function nedPos = enu2ned(enuPos)
nedPos = [enuPos(2), enuPos(1), -enuPos(3)];
end
