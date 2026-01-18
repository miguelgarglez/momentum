# CPU Diagnostics Context Pack

Copy this file into a new chat alongside the artifacts folder you want analyzed.

## Context (fill in)
- Goal:
- Date/time:
- Machine (model + CPU):
- macOS version:
- Release app version/build:
- Notes about workload during run:
  - Known hotspots to watch (if any):

## What was run
- Command used:
- Bundle ID:
- Run timestamp folder:
- Scenarios:

## What you observed
- Any obvious CPU spikes?
- Any scenario that looked “fixed”?
- Anything odd (app exits, permissions prompts, logs missing)?
 - Did the UI sidebar/detail appear “stale” (expected if refresh is throttled)?

## Artifacts to share
Paste these paths (or attach the files):
- diagnostics/runs/<timestamp>/SUMMARY.md
- diagnostics/runs/<timestamp>/RUN_INFO.md
- diagnostics/runs/<timestamp>/*/cpu.csv
- diagnostics/runs/<timestamp>/*/diagnostics.csv (from MOM_DIAG)
- diagnostics/runs/<timestamp>/*/logs.txt
- diagnostics/runs/<timestamp>/*/timeprofiler.trace (if available)
