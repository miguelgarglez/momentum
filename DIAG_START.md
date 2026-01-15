# Start Here — Automated CPU Diagnostic Run

Use this file to kick off a new chat and run the automated diagnostics.

## One‑liner to run
```bash
make diag-cpu-release
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
