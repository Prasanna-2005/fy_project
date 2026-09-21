# Multi-UAV Swarm Resilience Benchmark Suite

**Project Goal:** Reproduce and benchmark the algorithms from Zeng, Wu, Li, Zhuang (IEEE Systems Journal 2026): *"Enhancing UAV Swarm Resilience to Payload Failures: A Bidirectional Task Reallocation Approach"* (BDTR).

**Our Strategy:** Reactive Hungarian — a centralized LAP-based assignment with snapshot cost minimization, evaluated against 3 literature baselines (RRAM, BDTR, SROM) in a controlled, fair comparison environment.

**Last Updated:** 2026-09-21

---

## Project Structure

```
code/
├── CONTEXT.md              ← This file (project README & change log)
│
├── prototype/              ← Visual Prototype (GCS 3D Animation)
│   ├── 1_RRAM/             ← Baseline 1: Random Resource Allocation
│   │   ├── main.m          │   Launches visual simulator
│   │   └── sim.m           │   Simulation engine
│   ├── 2_BDTR/             ← Baseline 2: Bidirectional Task Reallocation
│   │   ├── main.m
│   │   └── sim.m
│   ├── 3_SROM/             ← Baseline 3: Li et al. 2023 Algorithm 1
│   │   ├── main.m
│   │   └── sim.m
│   ├── 4_HUNGARIAN/        ← OUR STRATEGY: Reactive Hungarian (LAP)
│   │   ├── main.m
│   │   └── sim.m
│   ├── common/             ← Shared config, rendering, metrics
│   │   ├── common_config.m
│   │   ├── initRender.m
│   │   ├── renderFrame.m
│   │   └── compute_paper_metrics.m
│   └── run_all_baselines.m ← Runs all 4 methods with fast-mode visual comparison
│
├── monte_carlo/            ← Headless Experimental Suite (Batch Benchmarking)
│   ├── 1_RRAM/             ← Baseline 1
│   │   ├── main.m
│   │   └── sim.m
│   ├── 2_BDTR/             ← Baseline 2
│   │   ├── main.m
│   │   └── sim.m
│   ├── 3_SROM/             ← Baseline 3
│   │   ├── main.m
│   │   └── sim.m
│   ├── 4_HUNGARIAN/        ← OUR STRATEGY
│   │   ├── main.m
│   │   └── sim.m
│   ├── common/             ← Shared config, metrics, attack event generator
│   │   ├── common_config.m
│   │   ├── compute_paper_metrics.m
│   │   └── generate_attack_events.m
│   ├── results/            ← Generated output, nested by type
│   │   ├── png/            ← plots and scorecards
│   │   ├── csv/            ← summary and raw-trial tables
│   │   ├── mat/            ← MATLAB archives
│   │   └── log/            ← batch logs
│   ├── run_monte_carlo.m       ← Experiment B: 300-run Monte Carlo benchmark
│   ├── run_attack_analysis.m   ← Experiment A: Parametric attack degradation sweep
│   ├── smoke_test.m            ← Rapid 1-shot sanity-check (developer tool)
│   └── inspect_results.m       ← Post-experiment metrics viewer & CSV exporter
│
└── wip_prototype/          ← Legacy/work-in-progress (can be ignored)
```

---

## Method Comparison

| # | Directory | Algorithm | Role | Source |
|---|-----------|-----------|------|--------|
| 1 | `1_RRAM` | Random Resource Allocation | **Baseline** | Constructed from BDTR paper behavioral description (see §1 below) |
| 2 | `2_BDTR` | Bidirectional Task Reallocation | **Baseline** | Zeng et al. 2026 — extracted (2 pseudocode typos corrected, see §2 below) |
| 3 | `3_SROM` | Soft Resource Optimization | **Baseline** | Li et al. 2023 Algorithm 1 (binary failure + permutation search) |
| 4 | `4_HUNGARIAN` | Reactive Hungarian (LAP) | **Our Strategy** | Project's centralized LAP-based allocator (see §3 below) |

---

## Experimental Suite

### Prototype (`prototype/`)
- **Purpose:** Qualitative visual verification — Ground Control Station (GCS) live 3D animation.
- **Scenario:** Canonical 4 UAVs, 3 Capabilities (Camera, Thermal, LiDAR), 10 Tasks.
- **Disruption:** Hardcoded 3-event capability loss schedule (t = 20s, 35s, 50s) in `common_config.m`.
- **Status:** ✅ PASS — All 4 methods execute cleanly with visualization.

### Monte Carlo (`monte_carlo/`)
- **Purpose:** Headless batch benchmarking matching Table II of Zeng et al. (2026).
- **Scenarios:**
  - Scenario 1 (Small): 5 UAVs, 2 Payloads (Camera, Thermal), 80 Tasks
  - Scenario 2 (Large): 10 UAVs, 3 Payloads (Camera, Thermal, LiDAR), 120 Tasks

#### Experiment A: `run_attack_analysis.m`
- Parametric attack sweep: 3 patterns (Random, Balanced, Directed) × 3 strengths (20%, 30%, 40%) × 2 scenarios × 10 trials per condition.
- Produces degradation response curves showing CRI and Completion Rate vs. Interruption Strength.
- Saves to `results/mat/`, `results/png/`, and `results/csv/`.

#### Experiment B: `run_monte_carlo.m`
- Authentic Monte Carlo benchmark: N_sim = 300 independent runs per scenario (Table II scale).
- `common_config.m` accepts `taskSeed` so each run has a unique, independent stochastic task set while guaranteeing paired comparison across all 4 methods via Common Random Numbers (CRN).
- Nominal attack: 30% random payload degradation (fixed budget; randomized UAV/slot/timing per run).
- Reports Mean ± Std and Medians for: completionRate, CRI, R_task, R_time, throughputRecovery.
- Saves to `results/mat/`, `results/png/`, and `results/csv/`.

#### Utilities
- **`smoke_test.m`**: Rapid 1-shot sanity-check (~1.5s) — verifies all 4 methods execute cleanly after code modifications. Not for publication data.
- **`inspect_results.m`**: Post-experiment metrics viewer. Loads `.mat` files, prints formatted tables, and exports/refreshes CSV files for Excel viewing. Usage: `inspect_results`, `inspect_results('mc')`, `inspect_results('atk')`.

---

## Metrics Computed

| Metric | Description |
|--------|-------------|
| `R_task` | Task completion resilience ratio |
| `R_time` | Time efficiency resilience ratio |
| `CRI` | Comprehensive Resilience Index = α·R_task + (1−α)·R_time, with α = 0.5 |
| `throughputRecovery` | Post-failure throughput recovery ratio |
| `completionRate` | Fraction of tasks successfully completed |
| `feasibilityRate` | Fraction of tasks with feasible assignment |
| `failedRate` | Fraction of tasks that failed/remained unassigned |
| `meanCompletionTime` | Average task completion time (seconds) |

---

## Physical Simplifications (Per Paper §V.A)

Flight maneuverability (T_fly) and communication latency (τ_comm) are **excluded** from simulation to isolate task reallocation and load-balancing behavior. This matches the BDTR paper's own experimental methodology.

---

## Verification Status

| Component | Status | Notes |
|-----------|--------|-------|
| Prototype (visual) | ✅ PASS | All 4 methods animate cleanly |
| Smoke test (monte_carlo) | ✅ PASS | All 4 methods × 2 scenarios execute headlessly |
| Experiment A (Attack Analysis) | ✅ PASS | 144+ smoke-test sims completed; degradation curves plotted |
| Experiment B (Monte Carlo) | ✅ PASS | 24+ smoke-test sims completed; distribution charts plotted |
| MATLAB Code Analyzer | ✅ 0 errors, 0 warnings | Only info-level perf hints (preallocate, logical indexing) |
| Plotting | ✅ Base MATLAB compatible | Uses bar, errorbar, plot — no Statistics Toolbox dependency |

---

## Change Log

### 2026-09-21 — Project Reorganization
- **Method reordering:** Hungarian (our strategy) moved from position 3 to position 4; SROM (baseline) moved from position 4 to position 3. This clearly distinguishes the 3 literature baselines (RRAM, BDTR, SROM) from our proposed method (Hungarian).
- **Directory renames:** `3_HUNGARIAN_REACTIVE/` → `4_HUNGARIAN/` and `4_SROM/` → `3_SROM/` in both `prototype/` and `monte_carlo/`.
- **Results output directory:** Created `monte_carlo/results/` subdirectory. All generated output files (`.png`, `.mat`, `.csv`) are now written to `results/` instead of cluttering the `monte_carlo/` root.
- **Renamed `run_all_baselines.m` → `smoke_test.m`** in `monte_carlo/` to clarify its purpose as a rapid developer sanity-check, not an experiment runner.
- **CONTEXT.md rewritten** as a living project README with directory map, method comparison, experiment descriptions, and this change log.

### 2026-09-16 — Metrics Accessibility
- Added automatic CSV export (`.csv`) alongside `.mat` saves for both experiments.
- Added native MATLAB `table` objects (`mcSummaryTable`, `mcTrialsTable`, `attackSummaryTable`) inside `.mat` files for `openvar()` inspection.
- Created `inspect_results.m` utility for post-experiment metrics viewing without re-running simulations.

### 2026-09-15 — Initial Headless Experimental Suite
- Decoupled `monte_carlo/` from `prototype/` as a fully headless batch benchmarking suite.
- Implemented Experiment A (parametric attack analysis) and Experiment B (Monte Carlo benchmark).
- Added `generate_attack_events.m` for stochastic failure generation with 3 attack patterns.
- Verified all 4 methods across both scenarios with smoke tests.

---

## Algorithm Specifications

### §1. RRAM — Constructed Specification

**Why constructed, not extracted:** Moshksar, Bayesteh & Khandani (2011) [BDTR ref 30] is an information-theoretic wireless comms paper on frequency-hopping spectrum sharing — it contains no UAV, task, queue, or allocation content whatsoever. BDTR's citation to it does not hold up under reading. The construction below follows only BDTR's own behavioral description of RRAM: "zero-information baseline... focuses solely on current task completion... employs a random selection mechanism that prioritizes task assignment speed over constraint feasibility."

**Note on feasibility checking:** BDTR says RRAM "bypasses constraint feasibility." The most conservative interpretation — and the one used here — is that RRAM still filters for hard capability matching (otherwise assignments would be physically invalid), but ignores load/queue constraints entirely.

```
Algorithm: Random Resource Allocation (RRAM)

Input:   Unassigned/AtRisk task k; UAV set U
Output:  Assignment decision (k → u_target or k remains unassigned)

1:  U_cap ← {u ∈ U | Ψ(k) ⊆ Φ_eff(u)}     ← capability check only
2:  if U_cap = ∅  then
3:      k remains unassigned
4:  else
5:      u_target ← uniform random draw from U_cap    ← no load/queue check
6:      Assign k → u_target unconditionally
7:  end if
```

**Characteristics:**
- Feasibility: capability matching only — Ψ(k) ⊆ Φ_eff(u)
- Load awareness: none — accepts unbounded queue growth on u_target
- Complexity: O(|U|) per task (to build U_cap), then O(1) to draw
- Termination: one pass over all unassigned/AtRisk tasks per event
- Tie-break: seeded PRNG — `idx = mod(task_id × 2654435761, |U_cap|)` (Knuth's multiplicative hash)

---

### §2. BDTR Algorithm — Verified Extraction

#### Model Setup (from paper Sections III.A–III.C)

- UAV set **U** = {u₁,...,uₙ}; payload types **L** = {l₁,...,lₖ}
- Static config **Φ**: U → 2^L (which physical payloads each UAV carries, fixed at mission start)
- Per-payload health **σ(uᵢ, lⱼ)** ∈ {0, 1}: 1 = operational, 0 = failed
- Effective payloads **Φ_eff(uᵢ)** = {lⱼ ∈ Φ(uᵢ) | σ(uᵢ, lⱼ) = 1}
- Task requirement **Ψ(q)** ⊆ L; execution feasibility: **TC(uᵢ, q)** = 1 iff Ψ(q) ⊆ Φ_eff(uᵢ)
- Capable set **Ucap(q)** = {u ∈ U | Ψ(q) ⊆ Φ_eff(u)}
- Each UAV has task queue **Qᵢ** with load **|Qᵢ|**
- Trigger: one or more payloads on **u_fail** become σ = 0 → some tasks in Q_fail become infeasible

#### Experimental Parameters (from Table II)

| Parameter | Value |
|---|---|
| Small scenario | 5 UAVs, 2 payload types, 80 tasks |
| Large scenario | 10 UAVs, 3 payload types, 120 tasks |
| Monte Carlo runs | 300 per scenario |
| Interruption strengths | 20%, 30%, 40% |
| Degradation rate Δ | 0.9 |
| Weight α | 0.5 (R_task vs R_time balance) |
| Realloc. gain γ | **0.5** (directly confirmed from Table II original image) |
| Physical constraints (T_fly, τ_comm) | **Excluded from simulation** |

```
Algorithm 1: Bidirectional Task Reallocation (BDTR)

Input:   UAV set U with task queues {Qᵢ};  Failed node u_fail
Output:  Optimised task queues {Qᵢ}

─── PHASE 1: Feasibility Restoration ────────────────────────────────────

1:  K_invalid ← {q ∈ Q_fail | Ψ(q) ⊄ Φ_eff(u_fail)}
2:  Sort K_invalid in descending order (by task priority, tiebreak by task index)
3:  Q_fail ← Q_fail \ K_invalid
4:  for each task k ∈ K_invalid  do
5:      U_cand ← {u ∈ U | Ψ(k) ⊆ Φ_eff(u)}
6:      if U_cand ≠ ∅  then         ⚠️ CORRECTED
7:          u_target ← argmin_{u ∈ U_cand} |Q_u|   [tiebreak: lowest UAV index]
8:          Q_{u_target} ← Q_{u_target} ∪ {k}
9:      end if
10: end for

─── PHASE 2: Residual Capacity Exploitation ─────────────────────────────

11: U_donor ← U \ {u_fail}
12: while True  do
13:     if U_donor = ∅  then  break  end if
14:     u_d ← argmax_{u ∈ U_donor} |Q_u|   [tiebreak: lowest UAV index]
15:     if |Q_d| − |Q_fail| ≤ 1  then  break  end if
16:     K_swap ← {q ∈ Q_d | Ψ(q) ⊆ Φ_eff(u_fail)}
17:     if K_swap ≠ ∅  then    ⚠️ CORRECTED
18:         k* ← select task from K_swap [earliest in Q_d, tiebreak: lowest task index]
19:         Q_d    ← Q_d    \ {k*}
20:         Q_fail ← Q_fail ∪ {k*}
21:     else
22:         U_donor ← U_donor \ {u_d}
23:     end if
24: end while
25: return {Qᵢ}
```

---

### §3. Reactive Hungarian Algorithm — Our Strategy

The centralized LAP/Hungarian allocator. Only the trigger timing differs between Static, Reactive, and Proactive strategies — the algorithm itself is identical.

```
Algorithm 2: Reactive Hungarian Assignment

Input:   Q       ← newly-considered tasks (unassigned + all persistent AtRisk)
         U       ← UAV set with current state
         C[j][i] ← cost matrix (task j to UAV i); C[j][dummy] = C_dummy
         F[j][i] ← feasibility flag (1 iff u_i ∈ F_j(t))

Output:  X[j][i] = 1  iff task j assigned to UAV i

1:  Set C[j][i] ← ∞  for all (j, i) where F[j][i] = 0
2:  Pad to square: expand C to max(|Q|, |U|+1) × max(|Q|, |U|+1),
    add u_dummy column with cost C_dummy for every task
3:  Run Hungarian algorithm on padded C
4:  X ← result matching
5:  return X
    (X[j][dummy] = 1  means task j is unassigned → AtRisk)
```

**Key properties:**
- Optimality: Optimal for the given cost matrix C_ij
- Complexity: O(N³) where N = |Q| + |U|
- Feasibility: Capability, resource, and deadline constraints
- Load-balancing: Via normalised C_ij cost terms
- Reactive Trigger: Fires when an existing task assignment loses feasibility

---

### §4. SROM Algorithm — Extracted from Li et al. 2023

SROM (Soft Resource Optimization Method, Li et al., Reliab. Eng. Syst. Saf. 237:109368, 2023), used by Zeng et al. as a unidirectional / platform-centric baseline.

From the source paper, not a substitute algorithm:
- **Assumption 2 (Attack), item 2:** after a UAV is attacked, all of its functions are paralyzed; partial paralysis is not considered. A payload failure is therefore treated as platform death.
- **Assumption 3:** leftover missions go only to undamaged UAVs that still have spare mission-execution capacity C. If that set Q_c is empty, the leftovers stay blocked.
- **Algorithm 1:** enumerate the μ! permutations of the failed UAV's unfinished missions T_remain and insert each mission, in that order, onto the Q_c UAV that maximises incremental return. Never assign back to the failed UAV.

μ! is exact for μ ≤ 7 (Li et al. leftover sets are a few missions; 7! = 5040). At BDTR queue depth, if μ > 7 we permute a priority prefix of length min(nSlots, 7) rather than switching to a different algorithm.

```
Algorithm 1: Solving Algorithm of SROM (Li et al. 2023)

Input:   R_U  ← undamaged UAVs
         T_remain ← unfinished missions of the attacked UAV
Output:  Updated mission list

1:  Q   ← undamaged UAVs
2:  Q_c ← {u ∈ Q | u has remaining capacity}
3:  if Q_c = ∅  then  T_remain stay blocked; return
4:  for each of the μ! permutations of T_remain  do
5:      for each mission k in that order  do
6:          insert k onto the Q_c UAV with maximum incremental return
7:          (skip if no capable UAV still has a spare slot)
8:      end for
9:      record total incremental return of this permutation
10: end for
11: commit the permutation with maximum return
```

---

### §5. Tie-Breaking — Lexicographic Ordering

Deterministic, reproducible resolution across all four algorithms:

- **Hungarian (Ours):** Primary: lowest task index j. Secondary: lowest UAV index i.
- **BDTR Phase 1 (argmin load):** Primary: lowest queue load. Secondary: lowest UAV index.
- **BDTR Phase 2 (argmax load):** Primary: highest queue load. Secondary: lowest UAV index.
- **SROM sort/target:** Sort tie: lowest task index. Target tie: lowest UAV index.
- **RRAM:** Seeded PRNG — `idx = mod(task_id × 2654435761, |U_cap|)`.

---

### §6. Comparison Table

| **Aspect** | **RRAM** | **BDTR** | **SROM** | **Hungarian (Ours)** |
|---|---|---|---|---|
| **Role** | Baseline | Baseline | Baseline | **Our Strategy** |
| **Source** | Constructed | Zeng et al. 2026 | Li et al. 2023 Algorithm 1 | Our project |
| **Core logic** | Random draw from U_cap | Phase 1: offload; Phase 2: load-balance | Binary platform death; μ! insert into Q_c | Min-cost perfect matching (LAP) |
| **Optimality** | None (stochastic) | Local (Lyapunov-proven) | Exhaustive over leftover permutations | **Optimal** for C_ij |
| **Complexity** | O(\|U\|) | O(N_Q · N_U · N_L) | O(μ! · μ · \|Q_c\|) | O(N³) |
| **Load-balancing** | None | Phase 1: argmin load; Phase 2: load-diff ≥ 2 | Incremental-return insertion under cap C | Via normalised C_ij costs |
| **Bidirectionality** | No | Yes (Phase 2 pulls tasks back) | No — unidirectional; failed UAV is dead | No |
| **Paper results** | 0.803 completion / 0.347 CRI | 0.829 completion / 0.862 CRI | 0.225 completion / 0.426 CRI | — |

---

### §7. Disclosure Wording

**SROM (Li et al. 2023):**
> "SROM is implemented from Li et al. (2023) Algorithm 1 and Assumption 2: a payload failure is treated as full platform paralysis; all unfinished missions of the struck UAV are reassigned by permutation search onto undamaged UAVs with spare capacity. The failed UAV is never used again. When the leftover set exceeds 7 missions, a priority prefix of the same μ! space is searched (Li et al. leftover sets are a handful of missions; BDTR queues can be deeper). Capability matching is retained because Zeng et al.'s tasks have payload types; Li et al. UAVs are homogeneous."

**RRAM Construction:**
> "RRAM (cited by Zeng et al. 2026 as ref [30]) is attributed to Moshksar, Bayesteh & Khandani (2011), an information-theoretic paper containing no task-allocation algorithm. We construct RRAM from the BDTR paper's own behavioral description: a zero-information baseline that randomly selects a capable UAV for each unassigned task without load-balancing checks."
