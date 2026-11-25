# BDTR Reproduction Protocol Specification

**Scope:** Formal experimental protocol for reproducing and evaluating Zeng, Wu, Li, and Zhuang (IEEE Systems Journal, 2026), *"Enhancing UAV Swarm Resilience to Payload Failures: A Bidirectional Task Reallocation Approach"* (BDTR), inside `SRC_CODE/monte_carlo_rca/`.

---

## 1. Experimental Profiles (`common/apply_v2_profile.m`)

1. **Exact Paper Reproduction Profile (`paper_aligned`):**
   - **Exclusion of Travel Time:** Flight time is removed (`cfg.sim.includeTravel = false`). UAVs service assigned tasks without spatial travel delay, matching Zeng et al. §V.A (*"Flight maneuverability ($T_{fly}$) and communication latency ($\tau_{comm}$) are excluded from simulation"*).
   - **Exclusion of Task Deadlines:** Per-task deadlines are set to infinity ($d_j = \infty$). The paper defines no deadline expiry mechanism.
   - **Single-Source Comparison:** Literature reproduction comparisons against Zeng et al.'s BDTR benchmark (**82.9%** completion, **0.862** CRI) are strictly conducted under `paper_aligned`.

2. **Before / Local Extension Profile (`realistic_local`):**
   - **Geometric Travel:** Retains 5 m/s 3D Euclidean flight (`cfg.sim.includeTravel = true`).
   - **Finite Deadlines:** Retains locally constructed staggered deadlines from `common_config.m` (`round(max(80, dist/5 + ceil(j/nUAV)*22 + 60 + 20*rand))`): **83–452 s** (Small) and **85–377 s** (Large) across benchmark seeds.
   - **Reporting Boundary:** Kept strictly separate as the "Before" realistic local baseline; never mixed into paper reproduction claims.

---

## 2. Statistical Protocol & Sample Size

- **Reproduction Sample Size:** $N = 300$ independent Monte Carlo runs per profile per scenario under Common Random Numbers (CRN).
- **Fleet & Task Scale (Table II):**
  - **Scenario 1 (Small):** 5 UAVs (8 total payload slots), 2 payload types (`Camera`, `Thermal`), 80 tasks, nominal capacity `16` tasks/UAV.
  - **Scenario 2 (Large):** 10 UAVs (19 total payload slots), 3 payload types (`Camera`, `Thermal`, `LiDAR`), 120 tasks, nominal capacity `12` tasks/UAV.
- **Disjoint Seed Scheme:**
  - **Calibration Block:** Seeds `10001:10030` (30 runs; used exclusively in `run_bdtr_attack_calibration.m` Stage 1).
  - **Fresh Validation Block:** Seeds `20001:20030` (30 runs; used exclusively in `run_bdtr_attack_calibration.m` Stage 2).
  - **Full Benchmark Block:** Seeds `si * 500000 + ri` for $ri \in [1, 300]$ in `run_bdtr_comparison.m`:
    - Small (`si = 1`): `500001` through `500300`
    - Large (`si = 2`): `1000001` through `1000300`
  - All seed blocks are strictly disjoint to prevent data snooping.

---

## 3. Metric Definitions (`common/compute_paper_metrics.m`)

- **Task Completion Rate:**
  $$\text{completionRate} = \frac{N_{\text{complete}}}{N_{\text{total}}}$$
  where $N_{\text{total}} = 80$ (Small) or $120$ (Large).
- **Unfinished Tasks:**
  $$\text{unfinishedRate} = \frac{N_{\text{unfinished}}}{N_{\text{total}}}$$
  Any task remaining in a UAV queue or at-risk pool when simulation reaches $t = t_{end}$ (`15.41%` Small and `15.87%` Large under `paper_aligned`).
- **Failed Tasks:**
  $$\text{failedRate} = \frac{N_{\text{failed}}}{N_{\text{total}}}$$
  **`failedRate = 0` by design** under `paper_aligned` ($d_j = \infty$), enforced via assertion in `smoke_test.m`. Under `realistic_local`, deadline timeouts yield `45.06%` (Small) and `52.02%` (Large).
- **Resilience Metrics (Eqs. 5–7):**
  - $R_{task}$: Priority-weighted completed value plus reallocation gain $\gamma N_{\text{realloc}}$ normalized by `sum(priority) + gamma * max(1, nAtRisk)`, with $\gamma = 0.5$.
  - $R_{time}$: Equilibrium recovery ratio $1 - (T_{\text{recover}} / \Delta T)$, where $\Delta T = t_{end} - t_{\text{start}}$.
  - $CRI = \alpha R_{task} + (1 - \alpha) R_{time}$ with $\alpha = 0.5$.
  - `throughputRecovery`: Salvage fraction `nRealloc / nAtRisk` $\in [0, 1]$ of the true at-risk set.

---

## 4. Mission Horizon & Calibrated Attack Schedule

- **Horizon Duration:** Fixed at $t_{end} = 450$ s across all runs; discrete step $\Delta t = 1.0$ s.
- **Overload Discount Factor:** $\Delta = 0.9$ (execution stretches by $1/\Delta$ when queue depth exceeds nominal capacity).
- **Calibrated Benchmark Attack (`run_bdtr_comparison.m`):**
  - **Pattern:** `random` payload-slot failure.
  - **Timing Window:** Normalized $[0.20, 0.70]$ of $t_{end}$ ($90$–$315$ s).
  - **Counts:** `6` of `8` slots (`75.0%`) in Small; `18` of `19` slots (`94.7%`) in Large.

---

## 5. Explicit Log of Paper Omissions, Assumptions & Code Deviations

| Parameter / Feature | Paper Specification | RCA Model Implementation | Justification / Impact |
|---|---|---|---|
| **Task Geometry** | Not mentioned | $100\times100\times25$ m (Small), $150\times150\times35$ m (Large) | Irrelevant in `paper_aligned` (travel disabled); active in `realistic_local`. |
| **Task Execution Times** | Not disclosed | Discrete uniform `[16, 24]` s (`16 + round(8*rand)`) | Nominal capacity (`2250` s Small, `4500` s Large) leaves operational buffer without attacks. |
| **Mission Horizon ($t_{end}$)** | Not disclosed | Fixed $t_{end} = 450$ s, $\Delta t = 1.0$ s | Standardized across both profiles and scenarios. |
| **Attack Event Schedule** | Strengths `20%`, `30%`, `40%`; patterns Random/Balanced/Directed | Calibrated: 6/8 Small, 18/19 Large, window `[0.20, 0.70]` | Tuned on `10001:10030` and validated on `20001:20030` (`run_bdtr_attack_calibration.m`). |
| **Flight Time ($T_{fly}$)** | Explicitly excluded (§V.A) | `cfg.sim.includeTravel = false` (`paper_aligned`) | Aligns simulation timeline with paper's abstraction. |
| **Task Deadlines** | Not mentioned | $d_j = \infty$ (`paper_aligned`) | Avoids inventing synthetic deadline drops during reproduction. |
| **In-Progress Head Filter** | Alg. 1 Phase 2 does not filter executing tasks | `BDTR/sim.m` lines 245–247 skip `qIdx == assignedTask && elapsed > 0` | Prevents pulling back an actively executing task; verified by `smoke_test.m` Unit Case 2. |

---

## 6. Suite Layout (`monte_carlo_rca/`)

- **Core Solver:** `BDTR/sim.m`, `BDTR/main.m`
- **Shared Engine:** `common/` (`common_config.m`, `apply_v2_profile.m`, `compute_paper_metrics.m`, `generate_attack_events.m`, `generate_attack_events_count.m`, `move_fleet_step.m`, `overload_params.m`, `stretched_exec.m`)
- **Top-Level Scripts (4):**
  1. `smoke_test.m` — Protocol invariants (`paper_aligned` vs. `realistic_local`), determinism, and Algorithm 1 unit verification.
  2. `run_bdtr_attack_calibration.m` — Calibration sweep (`10001:10030`) and held-out validation (`20001:20030`).
  3. `run_bdtr_comparison.m` — 300-run comparison (`paper_aligned` vs. `realistic_local`), exporting CSV/MAT and calling `plot_bdtr_comparison`.
  4. `plot_bdtr_comparison.m` — 4-panel PNG scorecard generator (`results/png/bdtr_before_vs_exact_paper.png`).
