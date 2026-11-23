# BDTR Reproduction Protocol Specification (V2)

**Scope:** Formal experimental protocol for reproducing and evaluating Zeng et al. (IEEE Systems Journal, 2026), *"Enhancing UAV Swarm Resilience to Payload Failures: A Bidirectional Task Reallocation Approach"* (BDTR).

---

## 1. Experimental Profiles

1. **Reproduction Profile (`paper_aligned`):**
   - **Exclusion of Travel Time:** Flight time is removed (`cfg.sim.includeTravel = false`). UAVs service assigned tasks immediately on assignment without spatial travel delay, matching the explicit methodology in Zeng et al. §V.A ("Physical constraints $T_{fly}$ and $\tau_{comm}$ are excluded from simulation").
   - **Exclusion of Task Deadlines:** Per-task deadlines are set to infinity ($d_j = \infty$). The paper defines no deadline expiry mechanism.
   - **Single-Source Comparison:** All comparisons against literature figures (BDTR 0.829, RRAM 0.803, SROM 0.225) are strictly conducted under `paper_aligned`.

2. **Local Extension Profile (`realistic_local`):**
   - **Geometric Travel:** Retains 5 m/s Euclidean flight over 3D coordinates.
   - **Finite Deadlines:** Retains locally constructed staggered deadlines ($80 \le d_j \le 420$ s).
   - **Reporting Boundary:** Kept strictly as a separate extension study; never mixed into the paper reproduction table.

---

## 2. Statistical Protocol & Sample Size

- **Reproduction Sample Size:** $N = 300$ independent Monte Carlo runs per algorithm per scenario under Common Random Numbers (CRN).
- **Fleet & Task Scale (Table II):**
  - **Scenario 1 (Small):** 5 UAVs, 2 payload types (Camera, Thermal), 80 tasks.
  - **Scenario 2 (Large):** 10 UAVs, 3 payload types (Camera, Thermal, LiDAR), 120 tasks.
- **Disjoint Seed Scheme:**
  - **Calibration Block:** Seeds `10001:10030` (used exclusively for tuning attack schedules; never used for benchmark reporting).
  - **Fresh Validation Block:** Seeds `20001:20030` (disjoint held-out seed set for validating calibrated attack parameters).
  - **Full Benchmark Block:** Seeds `si * 500000 + ri` for $ri \in [1, 300]$:
    - Small: `500001` through `500300`
    - Large: `1000001` through `1000300`
  - All blocks are strictly disjoint to prevent data snooping.

---

## 3. Metric Definitions

- **Task Completion Rate:**
  $$\text{completionRate} = \frac{N_{\text{complete}}}{N_{\text{total}}}$$
  where $N_{\text{total}} = 80$ (Small) or $120$ (Large).
- **Unfinished Tasks:**
  $$\text{unfinishedRate} = \frac{N_{\text{unfinished}}}{N_{\text{total}}}$$
  Counted separately. An unfinished task is any task that remains in a UAV queue or in the at-risk pool when simulation reaches $t = t_{end}$.
- **Failed Tasks:**
  $$\text{failedRate} = \frac{N_{\text{failed}}}{N_{\text{total}}}$$
  **failedRate = 0 by design** under `paper_aligned`. Because $d_j = \infty$, tasks never expire or fail due to deadline timeouts.
- **Resilience Metrics (Eqs. 5–7):**
  - $R_{task}$: Priority-weighted completed value plus reallocation gain $\gamma N_{realloc}$ normalized by theoretical maximum.
  - $R_{time}$: Equilibrium recovery time $1 - (T_{recover} / \Delta T)$ where $\Delta T = t_{end} - t_{start}$.
  - $CRI = \alpha R_{task} + (1 - \alpha) R_{time}$ with $\alpha = 0.5$.

---

## 4. Fixed Mission Horizon

- **Horizon Duration:** Fixed at $t_{end} = 450$ s across all runs.
- **Time Step:** $\Delta t = 1.0$ s.

---

## 5. Explicit Log of Paper Omissions & Local Assumptions

The BDTR paper omits several crucial simulation parameters. They are logged as explicit model assumptions:

| Parameter / Feature | Paper Specification | Local Model Assumption | Justification / Impact |
|---|---|---|---|
| **Task Geometry** | Not mentioned | $100\times100\times25$ m (Small), $150\times150\times35$ m (Large) | Irrelevant in `paper_aligned` since travel is excluded; retained for `realistic_local`. |
| **Task Execution Times** | Not disclosed | Discrete uniform $[16, 24]$ s | Sized to ensure nominal fleet capacity without attacks can service all tasks within $t_{end}$. |
| **Mission Horizon ($t_{end}$)** | Not disclosed | Fixed $t_{end} = 450$ s | Sized so that 80 tasks (1600s total work) across 5 UAVs (2250s available) have an operational buffer. |
| **Attack Event Schedule** | Strengths $20\%, 30\%, 40\%$; patterns Random/Balanced/Directed | Stochastic injection window $[t_{min}, t_{max}]$ | Calibrated systematically on a calibration seed block and verified on held-out seeds. |
| **Flight Time ($T_{fly}$)** | Explicitly excluded (§V.A) | `cfg.sim.includeTravel = false` | Directly aligns simulation timeline with paper's mathematical abstraction. |
| **Task Deadlines** | Not mentioned | $d_j = \infty$ | Avoids inventing synthetic deadline drops during reproduction. |
