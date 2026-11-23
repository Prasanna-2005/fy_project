function cfg = common_config(strategy, scenario, taskSeed)
% COMMON_CONFIG  Benchmark scenario configuration aligned with Table II
%                (Zeng et al. 2026):
%   - 'small': 5 UAVs, 2 payload types (Camera, Thermal), 80 tasks
%   - 'large': 10 UAVs, 3 payload types (Camera, Thermal, LiDAR), 120 tasks
%
% Usage:
%   cfg = common_config(strategy, scenario, taskSeed)
%   strategy: 'rram', 'bdtr', 'reactive', or 'srom' (default: 'reactive')
%   scenario: 'small' or 'large' (default: 'small')
%   taskSeed: integer seed for random task generation (default: 1001)

if nargin < 1 || isempty(strategy)
    strategy = 'reactive';
end
if nargin < 2 || isempty(scenario)
    scenario = 'small';
end
if nargin < 3 || isempty(taskSeed)
    taskSeed = 1001;
end

cfg.scenario = lower(scenario);
cfg.strategies = {strategy};

% Seeded generation for reproducible tasks
savedRng = rng();
rng(taskSeed, 'twister');

switch cfg.scenario
    case 'small'
        % ==============================================================
        % SCENARIO 1 (SMALL): 5 UAVs, 2 Payloads, 80 Tasks
        % ==============================================================
        cfg.capabilities = {'Camera', 'Thermal'};

        % Fleet: 5 UAVs clustered near launch base [15, 15, 10]
        cfg.uav(1) = struct('name','UAV1', 'position',[12 12 10], 'capabilities',{{'Camera','Thermal'}}, 'speed',5);
        cfg.uav(2) = struct('name','UAV2', 'position',[12 18 10], 'capabilities',{{'Camera'}},           'speed',5);
        cfg.uav(3) = struct('name','UAV3', 'position',[18 12 10], 'capabilities',{{'Thermal'}},          'speed',5);
        cfg.uav(4) = struct('name','UAV4', 'position',[18 18 10], 'capabilities',{{'Camera','Thermal'}}, 'speed',5);
        cfg.uav(5) = struct('name','UAV5', 'position',[15 15 12], 'capabilities',{{'Camera','Thermal'}}, 'speed',5);

        % 80 Tasks distributed in 100x100x25m space
        nT = 80;
        cfg.task = repmat(struct('name','', 'location',[0 0 0], 'requiredCap',{{}}, ...
            'execTime',20, 'priority',1, 'deadline',100, 'releaseTime',0), 1, nT);

        for j = 1:nT
            cfg.task(j).name = sprintf('Task%d', j);
            x = 8 + 84 * rand();
            y = 8 + 84 * rand();
            z = 4 + 20 * rand();
            cfg.task(j).location = round([x, y, z], 1);

            % 50/50 balance between Camera and Thermal
            if mod(j, 2) == 1
                cfg.task(j).requiredCap = {'Camera'};
            else
                cfg.task(j).requiredCap = {'Thermal'};
            end

            cfg.task(j).execTime = 16 + round(8 * rand()); % 16-24s
            cfg.task(j).priority = mod(j, 3) + 1;           % 1, 2, 3

            % Deadlines staggered up to 420s
            distFromBase = norm([x, y, z] - [15, 15, 10]);
            qSlotEst = ceil(j / 5); % 1..16 estimated queue depth
            cfg.task(j).deadline = round(max(80, (distFromBase / 5) + (qSlotEst * 22) + 60 + 20 * rand()));
            cfg.task(j).releaseTime = 0;
        end

        % Default 2 degradation events for standalone main.m testing
        cfg.capabilityChanges(1) = struct('uavIndex', 1, 'capability', 'Thermal', 'changeTime', 40);
        cfg.capabilityChanges(2) = struct('uavIndex', 4, 'capability', 'Camera',  'changeTime', 80);

        worldDiag = 100 * sqrt(3);
        cfg.sim.tEnd = 450; % Horizon sufficient for 80 tasks across 5 UAVs

    case 'large'
        % ==============================================================
        % SCENARIO 2 (LARGE): 10 UAVs, 3 Payloads, 120 Tasks
        % ==============================================================
        cfg.capabilities = {'Camera', 'Thermal', 'LiDAR'};

        % Fleet: 10 UAVs
        cfg.uav(1)  = struct('name','UAV1',  'position',[10 10 10], 'capabilities',{{'Camera','Thermal'}},         'speed',5);
        cfg.uav(2)  = struct('name','UAV2',  'position',[10 20 10], 'capabilities',{{'Camera','LiDAR'}},           'speed',5);
        cfg.uav(3)  = struct('name','UAV3',  'position',[20 10 10], 'capabilities',{{'Thermal','LiDAR'}},          'speed',5);
        cfg.uav(4)  = struct('name','UAV4',  'position',[20 20 10], 'capabilities',{{'Camera','Thermal','LiDAR'}}, 'speed',5);
        cfg.uav(5)  = struct('name','UAV5',  'position',[15 15 10], 'capabilities',{{'Camera'}},                   'speed',5);
        cfg.uav(6)  = struct('name','UAV6',  'position',[15 25 10], 'capabilities',{{'Thermal'}},                  'speed',5);
        cfg.uav(7)  = struct('name','UAV7',  'position',[25 15 10], 'capabilities',{{'LiDAR'}},                    'speed',5);
        cfg.uav(8)  = struct('name','UAV8',  'position',[25 25 10], 'capabilities',{{'Camera','Thermal'}},         'speed',5);
        cfg.uav(9)  = struct('name','UAV9',  'position',[12 18 12], 'capabilities',{{'Camera','LiDAR'}},           'speed',5);
        cfg.uav(10) = struct('name','UAV10', 'position',[18 12 12], 'capabilities',{{'Camera','Thermal','LiDAR'}}, 'speed',5);

        % 120 Tasks distributed in 150x150x35m space
        nT = 120;
        cfg.task = repmat(struct('name','', 'location',[0 0 0], 'requiredCap',{{}}, ...
            'execTime',20, 'priority',1, 'deadline',100, 'releaseTime',0), 1, nT);

        caps3 = {'Camera', 'Thermal', 'LiDAR'};
        for j = 1:nT
            cfg.task(j).name = sprintf('Task%d', j);
            x = 10 + 130 * rand();
            y = 10 + 130 * rand();
            z = 5 + 30 * rand();
            cfg.task(j).location = round([x, y, z], 1);

            cIdx = mod(j - 1, 3) + 1;
            cfg.task(j).requiredCap = {caps3{cIdx}};

            cfg.task(j).execTime = 16 + round(8 * rand());
            cfg.task(j).priority = mod(j, 3) + 1;

            distFromBase = norm([x, y, z] - [15, 15, 10]);
            qSlotEst = ceil(j / 10); % 1..12 estimated queue depth
            cfg.task(j).deadline = round(max(80, (distFromBase / 5) + (qSlotEst * 22) + 60 + 20 * rand()));
            cfg.task(j).releaseTime = 0;
        end

        cfg.capabilityChanges(1) = struct('uavIndex', 1, 'capability', 'Thermal', 'changeTime', 40);
        cfg.capabilityChanges(2) = struct('uavIndex', 3, 'capability', 'LiDAR',   'changeTime', 70);
        cfg.capabilityChanges(3) = struct('uavIndex', 4, 'capability', 'Camera',  'changeTime', 100);

        worldDiag = 150 * sqrt(3);
        cfg.sim.tEnd = 450;

    otherwise
        error('common_config:unknownScenario', 'Unknown scenario "%s". Use "small" or "large".', scenario);
end

rng(savedRng);

% ----------------------------------------------------------------------
% BDTR Table II parameters (Zeng et al. 2026)
% ----------------------------------------------------------------------
cfg.bdtr.gamma           = 0.5;   % Reallocation gain coefficient (γ ∈ [0,1])
cfg.bdtr.delta           = 0.9;   % Degradation/overload discount factor (Δ)
cfg.bdtr.alpha           = 0.5;   % CRI weight: R_task vs R_time balance
cfg.bdtr.nominalCapacity = ceil(numel(cfg.task) / numel(cfg.uav)); % Small: 16, Large: 12

% ----------------------------------------------------------------------
% Experiment A (Attack Sensitivity) & Experiment B (Monte Carlo) Parameters
% ----------------------------------------------------------------------
cfg.attackExp.strengths = [0.20, 0.30, 0.40];
cfg.attackExp.patterns  = {'random', 'balanced', 'directed'};
cfg.attackExp.nTrials   = 10;

cfg.mc.nRuns            = 300;   % Table II publication scale
cfg.mc.nominalStrength  = 0.30;  % Nominal disruption strength
cfg.mc.nominalPattern   = 'random';

% Cost function reference values (BDTR Table II normalized parameters)
cfg.cost.refDistance       = worldDiag;
cfg.cost.refSpeed          = 5;              % fleet speed (m/s)
cfg.cost.refExecTime       = 24;             % max task execTime
cfg.cost.refQueueLen       = cfg.bdtr.nominalCapacity; % tasks/UAV
cfg.cost.wDistance          = 0.5;   % weight: travel time
cfg.cost.wWorkload         = 0.3;   % weight: queue load
cfg.cost.wCompletion       = 0.2;   % weight: completion time
cfg.cost.disruptionPenalty = 0.4;   % disruption penalty
cfg.cost.dummyCost         = 1e6;   % C_dummy >> real cost

cfg.sim.dt        = 1;     % simulation time step (s)
cfg.sim.playback  = 0.05;  % wall-clock pause per step
cfg.sim.visualize = false; % Headless batch only for complete scenario evaluation

end
