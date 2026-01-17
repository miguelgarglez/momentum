# Scripts Guidelines

## Diagnostics Runner
`scripts/diag_run_release.sh` builds the Release app and runs deterministic CPU diagnostics across scenarios. It handles:
- Per-scenario app launch with env flags.
- CPU sampling to `cpu.csv`.
- Time Profiler capture to `timeprofiler.trace`.
- Log capture (`logs.txt`) and diagnostics copy (`diagnostics.csv` when present).
- Driver integration (`SCENARIO_DRIVER_PATH`) and copying `/tmp/momentum-diag/driver.log` to `driver.log`.

## Deterministic Driver
`scripts/diag_scenario_driver.sh` simulates repeatable activity:
- App switching (Safari/Preview/Finder)
- Domain and file rotations
- Momentum foreground intervals
It writes phase timing to `/tmp/momentum-diag/driver.log`, which the runner copies into each scenario folder.

## Common Usage
- Full run with driver:
  ```bash
  SCENARIO_DRIVER_PATH=./scripts/diag_scenario_driver.sh DIAG_FORCE_ACTIVE=1 make diag-cpu-release
  ```
- Focus run with driver:
  ```bash
  SCENARIO_DRIVER_PATH=./scripts/diag_scenario_driver.sh make diag-cpu-release-focus
  ```

## Notes
- If `driver.log` is empty, check `/tmp/momentum-diag/driver.log` for driver output.
- `DIAG_FORCE_ACTIVE=1` is recommended for consistent sampling.
