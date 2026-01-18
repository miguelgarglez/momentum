# Diagnostics Guidelines

## Purpose
This folder contains deterministic CPU diagnostics runs and supporting guides. Use it to measure CPU impact by scenario, compare suspects, and correlate CPU spikes with driver phases.

## Recommended Commands
- Full run (all scenarios + deterministic driver):
  ```bash
  SCENARIO_DRIVER_PATH=./scripts/diag_scenario_driver.sh DIAG_FORCE_ACTIVE=1 make diag-cpu-release
  ```
- Focused run (baseline + top suspects + deterministic driver):
  ```bash
  SCENARIO_DRIVER_PATH=./scripts/diag_scenario_driver.sh make diag-cpu-release-focus
  ```

## Key Environment Variables
- `SCENARIO_DRIVER_PATH`: path to deterministic driver (recommended).
- `DIAG_FORCE_ACTIVE=1`: disables idle checks for consistent activity.
- `CPU_SAMPLE_S`, `TIMEPROFILER_S`: override sample durations when needed.
- The runner scales driver phase durations to `CPU_SAMPLE_S` so CPU sampling covers all phases.
- `SCENARIOS`: comma-separated list to override scenarios.
- `DRIVER_MOMENTUM_MODE=foreground|pulse`: controls whether Momentum stays foregrounded during the momentum phase.
- `DRIVER_MOMENTUM_FOREGROUND_S`: how long to keep Momentum in front per slice (foreground mode).
- `DRIVER_APP_ROTATION`: comma-separated app names to rotate during the mixed phase (default includes Xcode, VS Code, Ghostty, Notes).
- `DIAG_PRESEED=1`: pre-populates the per-scenario store with diagnostics seed data before each run.
- `DIAG_UI=1`: enables lightweight UI activity inside Momentum (cycles project selection).
- `DIAG_UI_INTERVAL_S=6`: how often to cycle project selection when `DIAG_UI=1`.

## Output Structure
```
diagnostics/runs/<timestamp>/
  RUN_INFO.md
  SUMMARY.md
  <scenario>/
    cpu.csv
    logs.txt
    diagnostics.csv (if MOM_DIAG writes it)
    driver.log
    timeprofiler.trace
```

## How to Read Results
- `SUMMARY.md`: quick view of avg CPU and P95 by scenario.
- `cpu.csv`: raw samples used for deeper analysis.
- `driver.log`: phase timing from deterministic driver (idle/domain/file/mixed/momentum).
- `timeprofiler.trace`: CPU call stacks for deep dives.

## Suggested Analysis Flow
1) Compare scenario averages and P95 from `SUMMARY.md`.
2) Use `driver.log` + `cpu.csv` to compute per-phase stats.
3) Open `timeprofiler.trace` for baseline vs best-improving scenario.
4) Prioritize fixes where both average CPU and per-phase spikes drop.

## Known Hotspots & Fixes (2026-01-18)
- Hotspots: `Project.weeklySeconds`, `Project.decodeStrings(from:)`, `ContentView` sidebar/detail recompute.
- Effective fixes:
  - Cache project-derived stats and refresh them on a low cadence (e.g., 10 min) instead of on every SwiftUI update.
  - Refresh detail stats only on project focus + interval; show light loader if refresh is slow.
  - Cache decoded assignment arrays in `Project` to avoid repeated JSON decode.
- Writes: batching SwiftData saves helps, but UI recompute dominated baseline CPU.

## Quick Phase Analysis (optional)
Use a short script to compute per-phase CPU stats for a run:
```bash
python3 - <<'PY'
import csv, datetime as dt, re
from pathlib import Path

run_root=Path('diagnostics/runs/<timestamp>')
scenario='baseline'
phase_re=re.compile(r'^\[(\d\d):(\d\d):(\d\d)\] phase (\w+) (start|end)')
run_date=dt.date(2026,1,16)  # update if needed

def phase_intervals(driver_path):
    phases=[]
    with driver_path.open() as f:
        for line in f:
            m=phase_re.match(line.strip())
            if not m:
                continue
            hh,mm,ss,phase,kind=m.groups()
            ts=dt.datetime.combine(run_date, dt.time(int(hh),int(mm),int(ss))).timestamp()
            phases.append((phase,kind,ts))
    intervals={}
    starts={}
    for phase,kind,ts in phases:
        if kind=='start':
            starts[phase]=ts
        elif kind=='end' and phase in starts:
            intervals[phase]=(starts[phase],ts)
    return intervals

def cpu_samples(cpu_path):
    samples=[]
    with cpu_path.open() as f:
        r=csv.DictReader(f)
        for row in r:
            samples.append((int(row['timestamp']),float(row['cpu_percent'])))
    return samples

intervals=phase_intervals(run_root/scenario/'driver.log')
samples=cpu_samples(run_root/scenario/'cpu.csv')
for phase in ['idle','domain','file','mixed','momentum']:
    if phase not in intervals:
        continue
    start,end=intervals[phase]
    vals=[v for ts,v in samples if start <= ts <= end]
    if not vals:
        continue
    vals_sorted=sorted(vals)
    p95=vals_sorted[int(0.95*len(vals))-1]
    print(f"{phase}: n={len(vals)} mean={sum(vals)/len(vals):.2f} p95={p95:.2f}")
PY
```

You can auto-detect the run date from `RUN_INFO.md`:
```bash
python3 - <<'PY'
import csv, datetime as dt, re
from pathlib import Path

run_root=Path('diagnostics/runs/<timestamp>')
scenario='baseline'
phase_re=re.compile(r'^\[(\d\d):(\d\d):(\d\d)\] phase (\w+) (start|end)')

run_info=(run_root/'RUN_INFO.md').read_text()
ts_match=re.search(r'timestamp:\\s*(\\d{8})-(\\d{6})', run_info)
if not ts_match:
    raise SystemExit("Could not parse timestamp from RUN_INFO.md")
run_date=dt.datetime.strptime(ts_match.group(1), '%Y%m%d').date()

def phase_intervals(driver_path):
    phases=[]
    with driver_path.open() as f:
        for line in f:
            m=phase_re.match(line.strip())
            if not m:
                continue
            hh,mm,ss,phase,kind=m.groups()
            ts=dt.datetime.combine(run_date, dt.time(int(hh),int(mm),int(ss))).timestamp()
            phases.append((phase,kind,ts))
    intervals={}
    starts={}
    for phase,kind,ts in phases:
        if kind=='start':
            starts[phase]=ts
        elif kind=='end' and phase in starts:
            intervals[phase]=(starts[phase],ts)
    return intervals

def cpu_samples(cpu_path):
    samples=[]
    with cpu_path.open() as f:
        r=csv.DictReader(f)
        for row in r:
            samples.append((int(row['timestamp']),float(row['cpu_percent'])))
    return samples

intervals=phase_intervals(run_root/scenario/'driver.log')
samples=cpu_samples(run_root/scenario/'cpu.csv')
for phase in ['idle','domain','file','mixed','momentum']:
    if phase not in intervals:
        continue
    start,end=intervals[phase]
    vals=[v for ts,v in samples if start <= ts <= end]
    if not vals:
        continue
    vals_sorted=sorted(vals)
    p95=vals_sorted[int(0.95*len(vals))-1]
    print(f"{phase}: n={len(vals)} mean={sum(vals)/len(vals):.2f} p95={p95:.2f}")
PY
```

## Related Docs
- `DIAG_START.md` (quick start)
- `DIAG_CONTEXT.md` (analysis checklist)
- `diagnostics/SCENARIO_GUIDE.md` (driver phases and rationale)
