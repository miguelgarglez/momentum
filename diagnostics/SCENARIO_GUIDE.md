# Deterministic CPU Diagnostic Scenario (Driver v1)

Date: 2026-01-16

## Goal
Produce repeatable, high-signal CPU runs that exercise the known hotspots:
- crash recovery snapshot persistence
- SwiftData writes (sessions + summaries)
- domain/file resolution polling
- UI invalidations when Momentum is foregrounded

This guide complements `make diag-cpu-release` by adding a deterministic driver that simulates app switching, domain changes, and file changes on a fixed schedule.

## What This Scenario Exercises
- **Crash recovery path:** frequent context updates from app switching + domain/file changes.
- **SwiftData writes:** regular session flushes from app switches.
- **Domain resolver:** Safari URL rotation.
- **File resolver:** Preview file rotation.
- **UI render:** periodic foregrounding of Momentum.

## Setup (recommended)
Close heavy apps and disable notifications to reduce noise. Then run:

```
SCENARIO_DRIVER_PATH=./scripts/diag_scenario_driver.sh \
make diag-cpu-release-focus
```

Optional overrides:
- `DRIVER_DURATION_S=240` total duration
- `DRIVER_URLS=...` custom URL list
- `DRIVER_PHASE_IDLE_S`, `DRIVER_PHASE_DOMAIN_S`, `DRIVER_PHASE_FILE_S`, `DRIVER_PHASE_MIXED_S`, `DRIVER_PHASE_MOMENTUM_S`
- `DRIVER_MOMENTUM_APP=Momentum` (app name)
- `DRIVER_KEEP_AWAKE=1` keep system idle timer reset via `caffeinate -u`

Each scenario now uses a clean store path inside the app container and seeds deterministic data when `MOM_DIAG` runs, so results are comparable run-to-run.
Driver logs are written to `/tmp/momentum-diag/driver.log`.
The runner also sets `tracker.idleThreshold` high and reduces `tracker.detectionInterval` to 1s for more consistent activity.
By default it disables idle checks (`DIAG_FORCE_ACTIVE=1`), because the app caps idle threshold at 60 minutes.

## Scenario Phases (default)
1) **Idle (20s)**
   - Baseline idle while app is running.

2) **Domain rotation (80s)**
   - Focus Safari and rotate a fixed list of URLs every ~4s.
   - Exercises domain resolver + assignment resolution.

3) **File rotation (60s)**
   - Focus Preview and rotate through 3 PDFs.
   - Exercises file resolver + assignment resolution.

4) **Mixed switching (80s)**
   - Safari URL change → Preview file change → Finder, loop.
   - Exercises session flushing + crash recovery persistence.

5) **Momentum foreground (40s)**
   - Brings Momentum to front periodically.
   - Exercises UI render cost on active data.

## Tips for High-Signal Runs
- Run each scenario 2–3 times and compare medians, not single samples.
- Use the same machine state (power mode, apps open, display). 
- If you change any tracking settings, re-run all scenarios.

## Why This Is Reliable
- The workload is script-driven (no human timing variance).
- URLs and files are fixed and rotated deterministically.
- Each run follows the same phase schedule and duration.

## Next Enhancements (optional)
- Add a UI automation pass to open a project detail view (requires Accessibility permissions).
- Add a variant that forces extra flushes (shorter heartbeat interval for a single run).
