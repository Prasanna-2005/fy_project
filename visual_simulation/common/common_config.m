function cfg = common_config(strategy)
% COMMON_CONFIG  Visual Prototype Configuration:
%   - 4 UAVs, 3 Capabilities (Camera, Thermal, LiDAR)
%   - 10 Tasks with realistic spatial dispersion, deadlines, and priorities
%   - 3 Hardcoded Attack Events matching Monte Carlo 30% interruption strength
%   - Visualization ALWAYS enabled for Ground Control Station (GCS) demonstration
%
% strategy: 'rram', 'bdtr', 'reactive', or 'srom' (default: 'reactive')

if nargin < 1 || isempty(strategy)
    strategy = 'reactive';
end

cfg.capabilities = {'Camera', 'Thermal', 'LiDAR'};

% ----------------------------------------------------------------------
% UAV Fleet: 4 nodes clustered around launch base [15, 15, 10]
% ----------------------------------------------------------------------
cfg.uav(1) = struct('name','UAV1', 'position',[13 13 10], 'capabilities',{{'Camera','Thermal'}},         'speed',5);
cfg.uav(2) = struct('name','UAV2', 'position',[13 17 10], 'capabilities',{{'Camera'}},                   'speed',5);
cfg.uav(3) = struct('name','UAV3', 'position',[17 13 10], 'capabilities',{{'Camera','LiDAR'}},            'speed',5);
cfg.uav(4) = struct('name','UAV4', 'position',[17 17 10], 'capabilities',{{'Camera','Thermal','LiDAR'}}, 'speed',5);

% ----------------------------------------------------------------------
% Tasks: 10 waypoints across 100x100m operational space
% 3 Thermal tasks (1, 7, 9), 4 Camera tasks (2, 4, 5, 8), 3 LiDAR tasks (3, 6, 10)
% Priorities: 1=Low, 2=Med, 3=High
% ----------------------------------------------------------------------
cfg.task(1)  = struct('name','Task1',  'location',[35 25  8], 'requiredCap',{{'Thermal'}}, 'execTime',25, 'priority',2, 'deadline',80,  'releaseTime',0);
cfg.task(2)  = struct('name','Task2',  'location',[65 20 14], 'requiredCap',{{'Camera'}},  'execTime',20, 'priority',1, 'deadline',85,  'releaseTime',0);
cfg.task(3)  = struct('name','Task3',  'location',[25 65 11], 'requiredCap',{{'LiDAR'}},   'execTime',20, 'priority',3, 'deadline',90,  'releaseTime',0);
cfg.task(4)  = struct('name','Task4',  'location',[70 70 18], 'requiredCap',{{'Camera'}},  'execTime',20, 'priority',1, 'deadline',110, 'releaseTime',0);
cfg.task(5)  = struct('name','Task5',  'location',[45 45  9], 'requiredCap',{{'Camera'}},  'execTime',25, 'priority',2, 'deadline',100, 'releaseTime',0);
cfg.task(6)  = struct('name','Task6',  'location',[15 50 15], 'requiredCap',{{'LiDAR'}},   'execTime',25, 'priority',2, 'deadline',90,  'releaseTime',0);
cfg.task(7)  = struct('name','Task7',  'location',[80 50 13], 'requiredCap',{{'Thermal'}}, 'execTime',25, 'priority',3, 'deadline',100, 'releaseTime',0);
cfg.task(8)  = struct('name','Task8',  'location',[50 80 16], 'requiredCap',{{'Camera'}},  'execTime',20, 'priority',1, 'deadline',115, 'releaseTime',0);
cfg.task(9)  = struct('name','Task9',  'location',[20 30 12], 'requiredCap',{{'Thermal'}}, 'execTime',18, 'priority',3, 'deadline',75,  'releaseTime',0);
cfg.task(10) = struct('name','Task10', 'location',[85 30 10], 'requiredCap',{{'LiDAR'}},   'execTime',18, 'priority',2, 'deadline',110, 'releaseTime',0);

% ----------------------------------------------------------------------
% Capability-change Attack Events (Rich multi-node disruption)
% Matching 30% degradation strength (3 out of 8 total payload slots)
% ----------------------------------------------------------------------
cfg.capabilityChanges(1) = struct('uavIndex', 1, 'capability', 'Thermal', 'changeTime', 20);
cfg.capabilityChanges(2) = struct('uavIndex', 3, 'capability', 'LiDAR',   'changeTime', 35);
cfg.capabilityChanges(3) = struct('uavIndex', 4, 'capability', 'Camera',  'changeTime', 50);

cfg.strategies = {strategy};

% ----------------------------------------------------------------------
% BDTR Benchmark Parameters (Zeng et al. 2026 Table II)
% ----------------------------------------------------------------------
cfg.bdtr.gamma           = 0.5;   % Reallocation gain coefficient (γ)
cfg.bdtr.delta           = 0.9;   % Degradation discount factor (Δ)
cfg.bdtr.alpha           = 0.5;   % CRI weight: R_task vs R_time balance
cfg.bdtr.nominalCapacity = ceil(numel(cfg.task) / numel(cfg.uav)); % 3 tasks/UAV

% Cost function reference values (BDTR Table II normalized parameters)
cfg.cost.refDistance       = 100 * sqrt(3);  % world diagonal
cfg.cost.refSpeed          = 5;              % fleet speed (m/s)
cfg.cost.refExecTime       = 25;             % max task execTime
cfg.cost.refQueueLen       = cfg.bdtr.nominalCapacity; % tasks/UAV
cfg.cost.wDistance          = 0.5;   % weight: travel time
cfg.cost.wWorkload         = 0.3;   % weight: queue load
cfg.cost.wCompletion       = 0.2;   % weight: completion time
cfg.cost.disruptionPenalty = 0.4;   % disruption penalty
cfg.cost.dummyCost         = 1e6;   % C_dummy >> real cost

% Simulation & GCS Display Timing
cfg.sim.dt        = 1;     % simulation time step (s)
cfg.sim.tEnd      = 120;   % simulation end time (s)
cfg.sim.playback  = 0.05;  % wall-clock pause per step for smooth animation
cfg.sim.visualize = true;  % ALWAYS true in visual prototype

end
