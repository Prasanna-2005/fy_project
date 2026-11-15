# 00. Notation and Variable Conventions

This file fixes the names used throughout the walkthrough. A symbol always refers to the same MATLAB field below. In code citations, paths are relative to this checkout; the source-of-truth harness is `SRC_CODE/monte_carlo/`.

## Symbol map

| Symbol | MATLAB field or variable | Plain-English meaning |
|---|---|---|
| $U$ | `cfg.uav` when configured; `uavs` during a simulation | The list of all UAVs in the fleet. [Configuration](../../SRC_CODE/monte_carlo/common/common_config.m#L38-L42) [Runtime copy](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L284-L295) |
| $N$ | `numel(cfg.uav)`; often stored in a local such as `n` or `nU` | The number of UAV entries in the fleet. [Example](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L284-L288) |
| $u_i$ | `uavs(i)` | UAV number `i`, using its position in the UAV array. [Fleet construction](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L288-L295) |
| $\Phi(u_i)$ | `cfg.uav(i).capabilities` | The payloads fitted to UAV `i` before simulated failures. [Small fleet](../../SRC_CODE/monte_carlo/common/common_config.m#L38-L42) |
| $\Phi_{eff}(u_i)$ | `uavs(i).capabilities` at the current simulation time | The payloads UAV `i` can still use; the failure handler removes a failed payload from this list. [Failure update](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L340-L350) |
| $L$ | `cfg.capabilities` | The names of payload types used in the selected scenario. [Scenario definitions](../../SRC_CODE/monte_carlo/common/common_config.m#L34-L35) [Large scenario](../../SRC_CODE/monte_carlo/common/common_config.m#L83-L85) |
| $\Psi(k)$ | `tasks(k).requiredCap` (copied from `cfg.task(k).requiredCap`) | The payload type or types task `k` needs. [Task copy](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L304-L315) |
| $Q_{u_i}$ | `uavs(i).queue` | The ordered list of task-array indices assigned to UAV `i`. [Queue creation](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L284-L295) |
| $|Q_{u_i}|$ | `numel(uavs(i).queue)` | The number of tasks currently in UAV `i`'s queue. [Queue-length calculation](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L113-L115) |
| $k$ | `k`, used to index `tasks(k)` | A task's position in the MATLAB `tasks` array; queue entries store this index, not the text name such as `Task3`. [Queue assignment](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L117-L121) |
| $d_k$ | `tasks(k).deadline` | The time by which task `k` must be completed, in seconds. [Task fields](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L298-L315) |
| $p_k$ | `tasks(k).priority` | Task `k`'s numeric priority. The generator uses 1, 2, or 3; BDTR sorts larger numbers first, so this walkthrough calls 1 low, 2 medium, and 3 high. The code does not spell out those three words. [Generation](../../SRC_CODE/monte_carlo/common/common_config.m#L63-L64) [Descending sort](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L96-L98) |
| $e_k$ | `tasks(k).execTime` | The time spent doing task `k` after the UAV reaches it, in seconds. [Task fields](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L298-L315) [Execution update](../../SRC_CODE/monte_carlo/common/move_fleet_step.m#L39-L46) |
| $t$ | Loop variable `t` in `sim.m` | The current simulated time, in seconds. [Mission loop](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L34-L35) |
| $dt$ | `cfg.sim.dt` | The size of one simulation time step, in seconds; the benchmark default is 1 second. [Configuration](../../SRC_CODE/monte_carlo/common/common_config.m#L166-L168) |
| $t_{end}$ | `cfg.sim.tEnd` | The final simulated time, in seconds; the benchmark scenarios use 450 seconds. [Small scenario](../../SRC_CODE/monte_carlo/common/common_config.m#L78-L78) [Large scenario](../../SRC_CODE/monte_carlo/common/common_config.m#L128-L128) |
| $\alpha$ | `cfg.bdtr.alpha`; read by `compute_paper_metrics` | The weight used to balance task resilience and time resilience in CRI; the default is 0.5. [Configuration](../../SRC_CODE/monte_carlo/common/common_config.m#L139-L142) [Metric use](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L25-L28) |
| $\gamma$ | `cfg.bdtr.gamma`; read by `compute_paper_metrics` | The extra weight for completed tasks that were at risk after a payload failure; the default is 0.5. [Configuration](../../SRC_CODE/monte_carlo/common/common_config.m#L139-L141) [Metric use](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L30-L32) |
| $R_{task}$ | `metrics.R_task` / `pm.R_task` | A normalized score based on the priorities of completed tasks plus credit for rescued at-risk tasks. [Calculation](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L81-L93) |
| $R_{time}$ | `metrics.R_time` / `pm.R_time` | A score for how quickly the fleet returns to the benchmark's non-overloaded state after failures. [Calculation](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L72-L78) |
| $CRI$ | `metrics.CRI` / `pm.CRI` | The combined resilience score: $\alpha R_{task} + (1-\alpha)R_{time}$. [Calculation](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L105-L105) |
| $N_{at-risk}$ | `nAtRisk` | The number of distinct tasks that were queued on a UAV when it lost a payload those tasks required. [At-risk count](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L60-L62) |
| $N_{realloc}$ | `nRealloc` | The number of at-risk tasks that eventually completed. [Salvaged-task count](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L64-L69) |
| $T_{recover}$ | `T_recover` | The measured interval from the first failure until the detected recovery point. [Calculation](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L54-L55) [Recovery duration](../../SRC_CODE/monte_carlo/common/compute_paper_metrics.m#L72-L78) |

## Indices, units, and naming rules

- MATLAB array indices start at 1. The paper's displayed set notation likewise numbers UAVs and tasks from 1 (for example, $u_1,\ldots,u_{N_U}$). [Paper model](../../FY_PROJECT_DOCS/PAPERS_MD/1_BDTR.md#L72-L82)
- In this code, a task ID in a queue is an integer position into `tasks`; it is not looked up by the task's string `name`. Thus `k = 3` means `tasks(3)`, whose display name is often `Task3`. [Task names and fields](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L298-L315) [Queue stores `k`](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L117-L121)
- UAV IDs in events and assignments are also 1-based positions in `uavs` and `cfg.uav`. The task index and UAV index are different kinds of IDs. [Fleet construction](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L284-L295) [Event fields](../../SRC_CODE/monte_carlo/2_BDTR/sim.m#L120-L121)
- Position coordinates are metres; the configuration describes the task field in metres. Time fields and task execution/deadline values are seconds. UAV speed is metres per second (`m/s`), as stated for the configuration's speed reference; the movement update advances by `speed * dt`. [Scenario scale](../../SRC_CODE/monte_carlo/common/common_config.m#L44-L47) [Speed unit](../../SRC_CODE/monte_carlo/common/common_config.m#L157-L158) [Movement](../../SRC_CODE/monte_carlo/common/move_fleet_step.m#L19-L25)
- Use $u_i$ for one UAV and $k$ for one task throughout. Use `cfg.*` for configured values and `uavs`/`tasks` for their mutable simulation-time copies. Use $\Phi$ only for the configured payload list and $\Phi_{eff}$ only for the current, possibly degraded list.
- Some MATLAB helper functions reuse short loop variables such as `k` for unrelated arrays. In this walkthrough, $k$ always means a task index when the prose is about a task; the cited function context determines a loop variable's local meaning.
