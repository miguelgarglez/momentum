# Start Here — Automated CPU Diagnostic Run

Use this file to kick off a new chat and run the automated diagnostics.

## One‑liner to run
```bash
make diag-cpu-release
```

## With deterministic workload (recommended)
```bash
SCENARIO_DRIVER_PATH=./scripts/diag_scenario_driver.sh DIAG_FORCE_ACTIVE=1 make diag-cpu-release
```
This run uses an isolated store per scenario and seeds deterministic data automatically.
Note: the store lives inside the app sandbox container so macOS permissions do not block it.
The driver keeps the system idle timer reset (via `caffeinate -u`) unless disabled.
The runner sets `tracker.idleThreshold` high and `tracker.detectionInterval` to 1s for consistent activity.
By default it disables idle checks (`DIAG_FORCE_ACTIVE=1`) to avoid Momentum pausing.

## Focused run (recommended after a full run)
```bash
SCENARIO_DRIVER_PATH=./scripts/diag_scenario_driver.sh make diag-cpu-release-focus
```

You can also override scenarios and timing via env vars:
```bash
SCENARIOS="baseline,disable_swiftdata_writes" CPU_SAMPLE_S=240 TIMEPROFILER_S=90 make diag-cpu-release
```

## What this produces
```
diagnostics/runs/<timestamp>/
  RUN_INFO.md
  SUMMARY.md
  <scenario>/
    cpu.csv
    diagnostics.csv
    logs.txt
    timeprofiler.trace
```

## What to paste in the new chat
- This file: `DIAG_START.md`
- `DIAG_CONTEXT.md` (fill in the context section)
- The run folder:
  - `diagnostics/runs/<timestamp>/RUN_INFO.md`
  - `diagnostics/runs/<timestamp>/SUMMARY.md`
  - (optional) the whole `diagnostics/runs/<timestamp>/` directory if the model can read files

## Quick sanity check
If the run finishes, verify:
```bash
ls diagnostics/runs/$(ls -t diagnostics/runs | head -n1)
```
