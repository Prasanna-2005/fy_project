# PX4 SITL benchmark plan

From a clean machine to a fleet that MATLAB can command. No allocator code lives here. The 300-seed MATLAB table stays the combinatorial result. This setup is the flight check on top of it.

Official references:

- [PX4 Ubuntu development environment](https://docs.px4.io/main/en/dev_setup/dev_env_linux_ubuntu.html)
- [Gazebo simulation](https://docs.px4.io/main/en/sim_gazebo_gz/)
- [Multi-vehicle simulation with Gazebo](https://docs.px4.io/main/en/sim_gazebo_gz/multi_vehicle_simulation) — Linux only

## 1. What “done” means

Five `x500` quadrotors in one Gazebo world, each with its own PX4 instance. MATLAB, still running the existing allocators, reads position and payload health and uploads the next mission. A task is complete only when that vehicle has held the task point, with the required payload alive, for the full execution time. A reassigned task starts that clock at zero.

## 2. Machine

PX4 multi-vehicle Gazebo does not run natively on Windows. Use Ubuntu 22.04.

Preferred: a native Ubuntu 22.04 install, or a second drive. Gazebo’s 3D view is reliable there.

Acceptable: WSL2 Ubuntu 22.04 on this Windows PC, with WSLg for the Gazebo window. MATLAB stays on Windows. UDP between Windows and WSL2 is the link. If the Gazebo window is blank or five vehicles stutter, move the same install to native Ubuntu. Do not debug the allocators until one vehicle is visible and armed.

Leave at least 40 GB free and 16 GB RAM. Five SITL instances plus Gazebo is the small scenario (5 vehicles). The large scenario (10) is out of scope until the small one is stable.

## 3. Install the flight stack

On Ubuntu 22.04, after a normal desktop install:

```bash
sudo apt update
sudo apt install -y git

git clone https://github.com/PX4/PX4-Autopilot.git --recursive ~/PX4-Autopilot
bash ~/PX4-Autopilot/Tools/setup/ubuntu.sh
```

Log out and back in when the script says the user was added to groups. Then:

```bash
cd ~/PX4-Autopilot
make px4_sitl gz_x500
```

That one command builds PX4 SITL and installs Gazebo Harmonic through the setup script’s simulation packages. The first build is long. Success is a Gazebo window with one quadrotor and a PX4 console that reaches the ready state.

Stop it with Ctrl+C in that terminal.

Pin the git revision you built. Write the commit hash in the lab notebook. Later numbers are comparable only on that same revision.

## 4. Prove one vehicle before any MATLAB

Install QGroundControl on the same Ubuntu machine from the PX4 site. Start `make px4_sitl gz_x500` again. QGroundControl should connect on its own.

Check, in order:

1. The map shows one vehicle.
2. You can arm and take off from QGroundControl, then land.
3. You can upload a two-waypoint mission and the vehicle flies it.
4. The PX4 console prints the MAVLink UDP port. Write that port down. Later instances use their own ports. Read the printed port. Do not guess.

If QGroundControl cannot fly a mission, stop. MATLAB is not the next step.

## 5. Five vehicles, still without MATLAB

Build once:

```bash
cd ~/PX4-Autopilot
make px4_sitl
```

Start vehicle 1 so it also starts Gazebo. In four more terminals, start vehicles 2–5 in standalone mode so they join that same Gazebo server. Instance numbers and spawn poses must all differ. The pattern from the PX4 multi-vehicle page:

```bash
# terminal 1 — starts Gazebo
PX4_SYS_AUTOSTART=4001 PX4_SIM_MODEL=gz_x500 ./build/px4_sitl_default/bin/px4 -i 1

# terminals 2–5 — join the running Gazebo, each with its own pose and instance
PX4_GZ_STANDALONE=1 PX4_SYS_AUTOSTART=4001 PX4_GZ_MODEL_POSE="0,1" PX4_SIM_MODEL=gz_x500 ./build/px4_sitl_default/bin/px4 -i 2
```

`4001` is the x500 airframe. Shift `PX4_GZ_MODEL_POSE` so the five vehicles are not stacked. Match the MATLAB launch cluster as closely as the world allows: a few metres apart, not hundreds.

QGroundControl should list five vehicles. Arm and hover each one once. Then set the horizontal speed cap to 5 m/s on every instance (`MPC_XY_VEL_MAX`), which is the speed in `common_config.m`. Save the parameter on each instance. A faster default quadrotor would shrink travel time and make the MATLAB table incomparable.

Known snag: extra vehicles sometimes fail to arm because the simulated magnetometer looks duplicated. If a vehicle will not arm, check the PX4 forum note on `EKF2_MAG_CHECK` for multi-vehicle Gazebo, record the change, and apply the same change to every instance.

## 6. MATLAB side

MATLAB stays R2026a on Windows. It does not integrate the dynamics.

Install, if the licence already includes them:

- UAV Toolbox, for `mavlinkio`
- nothing else from the flight stack

If UAV Toolbox is not licensed, put a thin Python MAVLink process on Ubuntu (`pymavlink`) and let MATLAB talk to that process. Do not reimplement CARA, SABR, or BDTR in Python.

The MATLAB process is the ground station. Each allocator already returns a queue per vehicle. A separate adapter, written later, turns the head of each queue into a mission item. `move_fleet_step` does not run in this tier.

## 7. Connect Windows MATLAB to Ubuntu PX4

WSL2: forward the printed MAVLink UDP ports so Windows can reach them. Native Ubuntu: run MATLAB there, or point Windows MATLAB at the Ubuntu machine’s IP.

Connection check, one vehicle:

1. Start SITL.
2. From MATLAB, open that vehicle’s printed UDP port.
3. Print latitude, longitude, and relative altitude once a second for 10 seconds.
4. Upload a single waypoint 20 m north. The vehicle flies there and stops.

Then repeat for all five ports in one MATLAB session. Five independent links, five system ids. A broadcast that arms the wrong vehicle fails this check.

## 8. World, tasks, and payload health

Keep the MATLAB scenario generator as the source of tasks. Export one seed at a time: task position, required payload, execution time, deadline, priority. Convert local metres to the Gazebo frame with one fixed origin. Document the origin. Every method uses that same file.

Acceptance radius is 2 m. Dwell time is the task’s `execTime`. Both numbers are identical for RRAM, BDTR, SROM, Hungarian, SABR, and CARA. The MATLAB sim used a point match. This radius is a new physical tolerance, so it is reported next to every SITL number and is not silently compared with the 300-seed table.

Payload health is a bit the ground station and the logger both see. Stage 2 may flip that bit from the existing attack schedule. Stage 4, not stage 2, is where a Gazebo camera or thermal model actually stops publishing. Completing a camera task after that bit is false is a failed check, even if the vehicle is sitting on the point.

Command delay is real upload time, measured from the MATLAB send stamp to the vehicle’s mission-ack stamp. CARA’s 1.05 s window is compared with that measured age. It is not inserted as a `pause` inside the allocator.

## 9. What is logged

One folder per seed, per method. Minimum columns:

- time, vehicle id, position, armed, current mission index
- mission upload time, ack time
- payload bits
- task id, enter-radius time, leave-radius time, payload-alive flag while inside

Metrics are computed from this log with the same definitions as `compute_paper_metrics.m`. The planner’s predicted finish time is not an input.

Two extra columns, only in this tier:

- median command age
- fraction of completions whose time inside the radius is at least `execTime`

## 10. Experiment order

Do not start a later stage until the earlier one passes.

| Stage | Fleet | Seeds | Methods | Air | Question |
|---|---|---|---|---|---|
| 1. Logger | 5 | 1 small seed, open-loop replay of a MATLAB queue | CARA only | calm | Can the log rebuild completion, R_task, R_time, CRI, and salvage? |
| 2. Closed loop | 5 | that same seed | CARA, SABR, BDTR | calm | Does a payload death at 4 s of a 15 s pass get abandoned, and does the next vehicle start its clock at zero? |
| 3. Paired sample | 5 | 30 seeds, 30% random, same seeds as the MATLAB table | CARA, SABR, BDTR | calm | Do completion and CRI keep the same order as the 300-seed table? |
| 4. Disturbances | 5 | those 30 seeds, one factor at a time | CARA, SABR, BDTR | 5 m/s wind; then 0.5 s and 2 s extra delay; then 5% lost uploads | Which gap is dynamics, and which gap is the allocator? |

Directed payload attack is a separate 10-seed slice after stage 3, not a 900-run grid.

Stage 1 is not a ranking. Stage 4 rows are not folded into the 300-seed headline.

## 11. Pass rules

- QGroundControl flew one vehicle, then saw five.
- MATLAB read five positions and uploaded five distinct missions.
- Every method faces the same speed cap, radius, dwell rule, wind, and loss rate.
- A moved task’s on-station time is at least its execution time.
- A task inside the measured command window is not retargeted by CARA.
- The scorecard for stages 3 and 4 is computed from the flight log.

## 12. Out of scope until the table above is done

- 300 seeds in Gazebo
- the 10-vehicle scenario
- retuning CARA on SITL seeds
- claiming the Gazebo result replaces the MATLAB 300-seed table
