# 01. Common Setup

The headless benchmark runs a mission from time zero to a fixed end time. Each UAV has a position, speed, payload list, and ordered task queue. A task can be put in a queue only if that UAV has every payload the task requires; a payload failure removes that payload from the UAV's current list. [BDTR mission loop and state setup](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L17-L20) [Capability test and failure update](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L321-L352)

Use the symbols and index rules in [00_notation.md](00_notation.md) throughout the walkthrough. Unless stated otherwise, scenario positions and task locations are in metres, speeds are in metres per second, and mission times are in seconds. [Configuration units](../../SRC_CODE/monte_carlo/common/common_config.m#L44-L47) [Speed reference](../../SRC_CODE/monte_carlo/common/common_config.m#L157-L158)

## Fleet

The configuration creates each UAV as a MATLAB struct with a name, three-dimensional position, nominal `capabilities`, and speed. The small scenario has five UAVs and Camera/Thermal payloads; the large scenario has ten UAVs and also uses LiDAR. All configured UAVs move at 5 m/s. [Small fleet definitions](../../SRC_CODE/monte_carlo/common/common_config.m#L34-L42) [Large fleet definitions](../../SRC_CODE/monte_carlo/common/common_config.m#L83-L96)

| Scenario | UAV | Start position (m) | Nominal payloads | Speed (m/s) |
|---|---|---:|---|---:|
| Small | UAV1 | [12, 12, 10] | Camera, Thermal | 5 |
| Small | UAV2 | [12, 18, 10] | Camera | 5 |
| Small | UAV3 | [18, 12, 10] | Thermal | 5 |
| Small | UAV4 | [18, 18, 10] | Camera, Thermal | 5 |
| Small | UAV5 | [15, 15, 12] | Camera, Thermal | 5 |
| Large | UAV1 | [10, 10, 10] | Camera, Thermal | 5 |
| Large | UAV2 | [10, 20, 10] | Camera, LiDAR | 5 |
| Large | UAV3 | [20, 10, 10] | Thermal, LiDAR | 5 |
| Large | UAV4 | [20, 20, 10] | Camera, Thermal, LiDAR | 5 |
| Large | UAV5 | [15, 15, 10] | Camera | 5 |
| Large | UAV6 | [15, 25, 10] | Thermal | 5 |
| Large | UAV7 | [25, 15, 10] | LiDAR | 5 |
| Large | UAV8 | [25, 25, 10] | Camera, Thermal | 5 |
| Large | UAV9 | [12, 18, 12] | Camera, LiDAR | 5 |
| Large | UAV10 | [18, 12, 12] | Camera, Thermal, LiDAR | 5 |

The simulator copies the configured fleet into runtime state. Failures change the runtime payload list, not the nominal configuration table. [Runtime fleet copy](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L284-L296) [Payload removal](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L340-L350)

## Tasks

The small scenario generates 80 tasks in a 100-by-100-by-25 m field: each location is sampled within the configured bounds, then rounded to 0.1 m. Odd-numbered tasks require Camera and even-numbered tasks require Thermal. The large scenario generates 120 tasks in a 150-by-150-by-35 m field, cycling through Camera, Thermal, and LiDAR requirements. [Small task generation](../../SRC_CODE/monte_carlo/common/common_config.m#L44-L70) [Large task generation](../../SRC_CODE/monte_carlo/common/common_config.m#L100-L120)

For both scenarios, execution time is generated from 16 through 24 seconds, and priority is generated as 1, 2, or 3. Deadlines are computed from distance from the launch-area reference, an estimated queue position, and a random addition; they are not all the same. The generator explicitly sets every task's `releaseTime` to 0, so no task is released after time zero in the nominal generator. The simulation can handle later releases if a configuration supplies them, but that is not what this generator does. [Task fields and generation](../../SRC_CODE/monte_carlo/common/common_config.m#L46-L70) [Large task fields](../../SRC_CODE/monte_carlo/common/common_config.m#L100-L120) [Later-release handling](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L23-L27) [Runtime release check](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L36-L42)

Task locations, execution times, priorities, deadlines, payload requirements, and release times are copied from `cfg.task` into the runtime `tasks` array. A queue stores indices into that array. [Task-state construction](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L298-L317) [Queue assignment](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L117-L121)

## Payload failures

The attack generator first lists every UAV/payload combination as a separate payload slot. It chooses the number of slots to disable by rounding `strength * totalSlots`, with a minimum of one and a maximum equal to the number of slots. It then assigns each selected slot a failure time between 15% and 60% of the mission horizon, rounds that time to the simulation step, and returns the events as `(UAV index, payload name, change time)`. [Slot enumeration and count](../../SRC_CODE/monte_carlo/common/generate_attack_events.m#L19-L33) [Failure-time generation](../../SRC_CODE/monte_carlo/common/generate_attack_events.m#L108-L122)

- **Random:** choose the required number of payload slots uniformly at random across the fleet. [Random branch](../../SRC_CODE/monte_carlo/common/generate_attack_events.m#L36-L40)
- **Balanced:** shuffle each UAV's payload slots, then take turns across UAVs so failures are spread as evenly as the available slots allow. [Balanced branch](../../SRC_CODE/monte_carlo/common/generate_attack_events.m#L41-L68)
- **Directed:** count how often tasks require each payload type, then target the most demanded type first; within that type, randomize which UAV's slot fails first. If more failures are requested, proceed to the next most demanded type. [Directed branch](../../SRC_CODE/monte_carlo/common/generate_attack_events.m#L69-L105)

The attack sweep uses 20%, 30%, and 40% strengths. Monte Carlo uses one nominal condition: 30% random. Both experiment runners replace the default capability-change schedule with generated attack events before calling a method. [Attack sweep settings](../../SRC_CODE/monte_carlo/run_attack_analysis.m#L41-L48) [Monte Carlo settings](../../SRC_CODE/monte_carlo/run_monte_carlo.m#L49-L50) [Attack schedule passed into methods](../../SRC_CODE/monte_carlo/run_attack_analysis.m#L83-L96) [Monte Carlo schedule passed into methods](../../SRC_CODE/monte_carlo/run_monte_carlo.m#L83-L98)

The scenario configuration also contains fixed example failures for standalone runs: in the small scenario UAV1 loses Thermal at 40 s and UAV4 loses Camera at 80 s; in the large scenario UAV1 loses Thermal at 40 s, UAV3 loses LiDAR at 70 s, and UAV4 loses Camera at 100 s. The experiment runners replace those defaults as described above. [Small defaults](../../SRC_CODE/monte_carlo/common/common_config.m#L74-L78) [Large defaults](../../SRC_CODE/monte_carlo/common/common_config.m#L123-L128) [Runner override](../../SRC_CODE/monte_carlo/run_monte_carlo.m#L83-L98)

## Seeds and paired comparisons

A seed is a number that initializes MATLAB's random-number generator, so repeating the same seeded setup reproduces the same random choices. `common_config` saves the current random state, seeds task generation with `taskSeed`, then restores the previous state. [Seed setup](../../SRC_CODE/monte_carlo/common/common_config.m#L27-L28) [State restoration](../../SRC_CODE/monte_carlo/common/common_config.m#L134-L134)

For Monte Carlo run `ri` in scenario `sc`, the runner sets `runSeed = sc * 500000 + ri`. It generates one task world and one attack schedule from that seed, then passes the same attack events and the same run seed to every method. This is a paired comparison: methods face the same randomly generated tasks and failures within a run, so differences are not caused by one method receiving an easier random world. [Monte Carlo seed and shared attack schedule](../../SRC_CODE/monte_carlo/run_monte_carlo.m#L78-L85) [Same seed/events supplied per method](../../SRC_CODE/monte_carlo/run_monte_carlo.m#L87-L98)

In the attack sweep, each pattern/strength/trial combination gets a deterministic seed for its failure schedule. The calls to `common_config` omit `taskSeed`, so each uses its default task seed; tasks stay the same across those conditions, while the generated attack schedule changes with the trial seed. [Sweep seed and attack creation](../../SRC_CODE/monte_carlo/run_attack_analysis.m#L79-L84) [Default task seed](../../SRC_CODE/monte_carlo/common/common_config.m#L7-L20) [Per-method config and shared schedule](../../SRC_CODE/monte_carlo/run_attack_analysis.m#L86-L96)

## Metrics

The simulation's final status for each task is used to calculate the following quantities:

| Metric | Plain-English meaning | How this code calculates it |
|---|---|---|
| Completion rate | The fraction of all tasks that finished before the run ended. | Count tasks whose status is `complete`, divided by the total task count. [Calculation](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L363-L379) |
| $R_{task}$ | A score for completed mission value, with an extra credit for at-risk tasks that were eventually completed. | Sum the priorities of completed tasks, add $\gamma$ times the number of completed at-risk tasks, then divide by total priority plus $\gamma$ times `max(1, nAtRisk)`; cap at 1. [Calculation](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L81-L93) |
| $R_{time}$ | A score for how quickly the fleet leaves its overloaded state after a failure. | Measure from the first failure to the detected recovery point, divide by the remaining horizon, subtract from 1, and floor at 0. Recovery is detected after the last failure when no queue exceeds nominal capacity for at least `max(dt, 5)` seconds; if this never happens, the recovery time is the end of the run. [Score](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L54-L55) [Recovery score](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L72-L78) [Recovery detection](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L163-L182) |
| CRI | The single combined resilience score. | `alpha * R_task + (1-alpha) * R_time`; with the default $\alpha=0.5$, both parts have equal weight. [Calculation](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L105-L105) [Default weight](../../SRC_CODE/monte_carlo/common/common_config.m#L139-L142) |
| Throughput recovery | The fraction of tasks that were at risk at payload failure and later finished. | `nRealloc / nAtRisk`; if there were no at-risk tasks, the code returns 1. [Calculation](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L64-L69) [Ratio](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L97-L103) |
| Feasibility rate | The fraction of tasks either completed or still assigned to a UAV that currently has every required payload. | Count complete tasks plus still-assigned tasks whose assigned UAV passes the payload check, divided by total tasks. [Calculation](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L366-L377) |
| Mean completion time | The average recorded completion time among tasks that finished. | Take the mean of `completeTime` for complete tasks; if none finished, return `NaN` (not a number). [Calculation](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L383-L388) |

One important distinction: this implementation's `throughputRecovery` is a rescued-task fraction, not a measurement of the whole fleet's raw work rate. The helper identifies tasks that were on the failed UAV and required the lost payload, then counts how many of those tasks eventually completed. [Metric definition](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L11-L18) [At-risk task replay](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L112-L151)

## Experiment sizes

**The prompt's five-method count does not match the current `monte_carlo/` code.** Both runners list six methods: the five named in the prompt plus `6_CARA`. The totals below use the six actual method rows and the loop dimensions in each runner. [Monte Carlo method list](../../SRC_CODE/monte_carlo/run_monte_carlo.m#L31-L39) [Attack-sweep method list](../../SRC_CODE/monte_carlo/run_attack_analysis.m#L24-L32)

For Experiment A, “conditions” means the 3 attack patterns crossed with the 3 strengths, or 9 combinations per scenario. With 2 scenarios there are 18 scenario-specific combinations; each combination runs 10 trials for each method.

| Experiment | Scenarios | Conditions | Runs per condition | Runs per method | Methods | Total runs |
|---|---:|---:|---:|---:|---:|---:|
| B: Monte Carlo (nominal, 30% random) | 2 (small, large) | 1 | 300 | 600 | 6 | 3,600 |
| A: Attack sweep | 2 | 3 patterns × 3 strengths = 9 | 10 | 180 | 6 | 1,080 |

Experiment B uses `2 scenarios * 6 methods * 300 runs = 3,600` method simulations. [Run count and total formula](../../SRC_CODE/monte_carlo/run_monte_carlo.m#L25-L65) Experiment A uses `2 scenarios * 6 methods * 3 patterns * 3 strengths * 10 trials = 1,080` method simulations. [Sweep dimensions and total formula](../../SRC_CODE/monte_carlo/run_attack_analysis.m#L41-L64)

## Shared tiny scenario

This deliberately small, hand-authored scenario will be reused in each method walkthrough. It is a teaching fixture, not one of the generated benchmark scenarios. Both UAVs start with Camera and Thermal, fly at 1 m/s, and use a 1-second time step. UAV1 loses Thermal at $t=12$ s. Four tasks are initially released at $t=0$; each takes 2 seconds to execute, has deadline 200 s, and has low priority ($p_k=1$). The task locations are far enough away that none has reached its execution point by the failure time.

| UAV | Start position (m) | Nominal payloads | Speed (m/s) |
|---|---:|---|---:|
| U1 | [0, 0, 0] | Camera, Thermal | 1 |
| U2 | [10, 0, 0] | Camera, Thermal | 1 |

| Task | Location (m) | Required payload | Execution time (s) | Deadline (s) | Priority | Release time (s) |
|---|---:|---|---:|---:|---:|---:|
| T1 | [100, 0, 0] | Camera | 2 | 200 | 1 | 0 |
| T2 | [100, 10, 0] | Camera | 2 | 200 | 1 | 0 |
| T3 | [100, 20, 0] | Thermal | 2 | 200 | 1 | 0 |
| T4 | [100, 30, 0] | Camera | 2 | 200 | 1 | 0 |

The fixture is designed so that after U1 loses Thermal, T3 is invalid there and must be offloaded. Once it is offloaded, U2's queue contains two Camera tasks that U1 can still do; this makes it possible to see how a method chooses between alternatives. The exact BDTR choices and a MATLAB run of this fixture are documented in [03_BDTR.md](03_BDTR.md).
