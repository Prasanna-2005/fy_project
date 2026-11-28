# BDTR Baseline Runner

## 1. File Roles

- `V2/shared/config/experiment_config.m` — Single shared configuration for scenarios (`small`, `large`), attack strategies (`Random`, `Balanced`, `Direct`), interruption strengths (`[0.40, 0.55, 0.70]`), Monte Carlo settings (`Random`, `0.55`, `300` runs), seed rules, outcomes, and plot settings.
- `V2/shared/generators/common_config.m` — Scenario builder (5/10 UAVs, 80/120 tasks, `includeTravel = true` @ 5 m/s, finite deadlines).
- `V2/shared/generators/generate_attack_events.m` — Deterministic (seeded) attack event generator (`random`, `balanced`, `directed` over `[0.15, 0.60]` of `tEnd`).
- `V2/shared/generators/generate_datasets.m` — Generates read-only `.mat` datasets (`attack_small.mat`, `attack_large.mat`, `mc_small.mat`, `mc_large.mat`) into `V2/shared/datasets/` and verifies seeds `1:30` pairing across all 9 attack configurations.
- `V2/BDTR/matlab/sim.m` — Unmodified BDTR Algorithm 1 implementation (`result = sim(cfg, 'bdtr')`).
- `V2/BDTR/matlab/move_fleet_step.m`, `compute_paper_metrics.m`, `overload_params.m`, `stretched_exec.m` — Runtime helpers for `sim.m`.
- `V2/BDTR/matlab/run_bdtr_attack.m` — Executes the 540 Attack runs (`2` scenarios $\times$ `9` configs $\times$ `30` seeds `1:30`) and writes `V2/results/BDTR/attack/bdtr_attack_runs.csv`.
- `V2/BDTR/matlab/run_bdtr_mc.m` — Executes the 600 Monte Carlo runs (`2` scenarios $\times$ `300` seeds `1001:1300`) and writes `V2/results/BDTR/montecarlo/bdtr_mc_runs.csv`.
- `V2/shared/plotting/plot_results.m` — Algorithm-agnostic 300 dpi PNG plot generator writing Figures 1–4 to `V2/plots/BDTR/`.

## 2. How to Run

```matlab
% 1. Generate shared datasets (only if V2/shared/datasets/ is empty)
cd('V2/shared/generators');
generate_datasets;

% 2. Run BDTR experiments
cd('V2/BDTR/matlab');
run_bdtr_attack;
run_bdtr_mc;

% 3. Generate plots (PNG 300 dpi)
addpath('V2/shared/plotting');
plot_results("BDTR");
```

## 3. Decision Log

- **Physics & Travel:** Travel is always enabled (`cfg.sim.includeTravel = true`, 5 m/s) with staggered finite deadlines (`83–452` s Small, `85–377` s Large).
- **Changes to Copied V1 Files (no algorithm logic altered):**
  - `V2/BDTR/matlab/move_fleet_step.m`: Removed the `paper_aligned` / `includeTravel` conditional branch (original V1 lines 18–25 and lines 36–39); 5 m/s geometric travel now executes unconditionally.
  - `V2/shared/generators/common_config.m`: Added `cfg.sim.includeTravel = true;  % 5 m/s` at line 167.
  - `sim.m`, `compute_paper_metrics.m`, `overload_params.m`, `stretched_exec.m`, and `generate_attack_events.m` are unchanged from V1.
- **Outcomes & Labels:** Every task finishes in one of three mutually exclusive states (`completionRate + failedRate + unfinishedRate == 1`, asserted per run with tolerance `1e-9`):
  - `completionRate`: `"completed"`
  - `failedRate`: `"failed by deadline"`
  - `unfinishedRate`: `"unfinished at horizon (tEnd)"` (computed by runners from `res.tasks` because `sim.m` omits it from `result.metrics`).
- **CRI / `R_time` Queue-Pruning Note (`realistic_local`):** Under finite deadlines (travel enabled at 5 m/s), `compute_paper_metrics.m` (`detectThroughputEquilibrium`, lines 245–251) clears expired tasks (`deadline(j) <= t`) from `assigned(j)`, shrinking virtual queue lengths before the work finishes and inflating `R_time` / `CRI` when deadline misses are heavy.
- **Seed Rules:** `instanceSeed = seed`, `attackSeed = seed + 100000`. Explicit `rng(..., 'twister')` precedes every `common_config` and `generate_attack_events` call because `generate_attack_events.m` ends with `rng('shuffle')` (line 144).
- **Warning Suppression:** Runners suppress benign warnings from unmodified `sim.m:5` (`addpath('../common')`) and MATLAB's built-in `sim` shadow via `onCleanup`.
- **Plots:** 300 dpi PNG only in `V2/plots/BDTR/`:
  1. `fig1_attack_heatmap.png` — Attack matrix heatmap (`completionRate` across 3 strategies $\times$ 3 strengths).
  2. `fig2_mc_distributions.png` — Monte Carlo completion rate distributions (`Random`, strength `0.55`, $n = 300$).
  3. `fig3_mc_metrics.png` — Monte Carlo summary (`CRI`, `R_time`, `R_task`): mean dot and 95% $z$-interval (`mean ± 1.95996 × SD / sqrt(300)`) for `Small` and `Large` (`Random`, strength `0.55`), using shared y-axis range `[0.4, 0.8]`.
     - **Printed Monte Carlo means (`n = 300`):**
       - `CRI`: Small `0.6395` (`0.639506`), Large `0.5732` (`0.573182`)
       - `R_time`: Small `0.6202` (`0.620230`), Large `0.5321` (`0.532086`)
       - `R_task`: Small `0.6588` (`0.658781`), Large `0.6143` (`0.614279`)
  4. `fig4_cri_vs_attack.png` — Mean `CRI` vs. payload slots lost (`Small`: `3, 4, 6`; `Large`: `8, 10, 13`; strengths `0.40, 0.55, 0.70`) across `Random`, `Balanced`, and `Direct` with 95% $t$-interval (`df = 29`, `t = 2.04523`) and shared y-axis `[0.4, 0.8]`.
     - **Caption:** Attacks are drawn across the timing window `[0.15, 0.60]` of the horizon, not applied one after another in time. `'Slots lost'` is the number of failed `(UAV, payload)` slots. `CRI` is affected by the queue-pruning artifact under `realistic_local`.
