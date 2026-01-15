#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="${BUNDLE_ID:-miguelgarglez.Momentum}"
APP_NAME="${APP_NAME:-Momentum}"

TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
RUN_ROOT="${ROOT_DIR}/diagnostics/runs/${TIMESTAMP}"
mkdir -p "${RUN_ROOT}"

BUILD_LOG="${RUN_ROOT}/build.log"
make -C "${ROOT_DIR}" build CONFIGURATION=Release >"${BUILD_LOG}" 2>&1

GIT_SHA="unknown"
GIT_BRANCH="unknown"
if git -C "${ROOT_DIR}" rev-parse --short HEAD >/dev/null 2>&1; then
  GIT_SHA="$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"
  GIT_BRANCH="$(git -C "${ROOT_DIR}" rev-parse --abbrev-ref HEAD)"
fi

PROJECT="Momentum.xcodeproj"
SCHEME="Momentum"
DESTINATION="platform=macOS"
DERIVED_DATA="${ROOT_DIR}/.derivedData"

BUILD_DIR=$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}" -configuration Release -showBuildSettings \
  | awk -F ' = ' '/BUILT_PRODUCTS_DIR/ {print $2; exit}')
FULL_PRODUCT_NAME=$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}" -configuration Release -showBuildSettings \
  | awk -F ' = ' '/FULL_PRODUCT_NAME/ {print $2; exit}')
APP_PATH="${BUILD_DIR}/${FULL_PRODUCT_NAME}"
APP_EXEC="${APP_PATH}/Contents/MacOS/${APP_NAME}"

if [[ ! -x "${APP_EXEC}" ]]; then
  echo "App binary not found at ${APP_EXEC}" >&2
  exit 1
fi

scenarios=(
  "baseline:"
  "disable_idle_check:DISABLE_IDLE_CHECK=1"
  "disable_heartbeat:DISABLE_HEARTBEAT=1"
  "disable_budget_monitor:DISABLE_BUDGET_MONITOR=1"
  "disable_backfill:DISABLE_BACKFILL=1"
  "disable_crash_recovery:DISABLE_CRASH_RECOVERY=1"
  "disable_swiftdata_writes:DISABLE_SWIFTDATA_WRITES=1"
  "disable_overlay_updates:DISABLE_OVERLAY_UPDATES=1"
)

RUN_INFO="${RUN_ROOT}/RUN_INFO.md"
cat <<EOF_RUN >"${RUN_INFO}"
# Run Info

- timestamp: ${TIMESTAMP}
- git_branch: ${GIT_BRANCH}
- git_sha: ${GIT_SHA}
- bundle_id: ${BUNDLE_ID}
- app_exec: ${APP_EXEC}
- run_root: ${RUN_ROOT}
- diagnostics_log: ~/Library/Logs/Momentum/diagnostics.csv
- warmup_s: 30
- cpu_sample_s: 120
- cpu_sample_interval_s: 2
- timeprofiler_s: 60
- scenarios:
EOF_RUN
for scenario in "${scenarios[@]}"; do
  name="${scenario%%:*}"
  flags="${scenario#*:}"
  echo "  - ${name}: ${flags}" >>"${RUN_INFO}"
done
{
  echo
  echo "## System"
  sw_vers || true
  echo
  uname -a || true
} >>"${RUN_INFO}"

log_supports_signpost=false
if log stream --help 2>&1 | rg -q -- "--signpost"; then
  log_supports_signpost=true
fi

run_scenario() {
  local name="$1"
  local flags="$2"
  local scenario_dir="${RUN_ROOT}/${name}"
  mkdir -p "${scenario_dir}"

  osascript -e "tell application id \"${BUNDLE_ID}\" to quit" 2>/dev/null || true
  sleep 2

  local diag_csv="${HOME}/Library/Logs/Momentum/diagnostics.csv"
  rm -f "${diag_csv}"

  local log_file="${scenario_dir}/logs.txt"
  local log_cmd=(log stream --style compact --predicate "subsystem == \"${BUNDLE_ID}\"")
  if [[ "${log_supports_signpost}" == "true" ]]; then
    log_cmd+=(--signpost)
  fi
  "${log_cmd[@]}" >"${log_file}" 2>&1 &
  local log_pid=$!

  # Launch app with env vars
  set +u
  env MOM_DIAG=1 ${flags} "${APP_EXEC}" >"${scenario_dir}/app_stdout.log" 2>"${scenario_dir}/app_stderr.log" &
  local app_pid=$!
  set -u

  local pid="${app_pid}"
  for _ in $(seq 1 30); do
    if ps -p "${pid}" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if ! ps -p "${pid}" >/dev/null 2>&1; then
    echo "Failed to start ${APP_NAME} for ${name}" >>"${scenario_dir}/errors.log"
    kill "${log_pid}" 2>/dev/null || true
    return
  fi

  sleep 30

  local trace_path="${scenario_dir}/timeprofiler.trace"
  xcrun xctrace record --template "Time Profiler" --attach "${pid}" --time-limit 60s \
    --output "${trace_path}" >"${scenario_dir}/timeprofiler.log" 2>&1 || \
    echo "Time Profiler failed for ${name}" >>"${scenario_dir}/errors.log"

  local cpu_csv="${scenario_dir}/cpu.csv"
  echo "timestamp,cpu_percent" >"${cpu_csv}"
  local start_ts
  start_ts=$(date +%s)
  local end_ts=$((start_ts + 120))
  while [[ $(date +%s) -lt ${end_ts} ]]; do
    if ! ps -p "${pid}" >/dev/null 2>&1; then
      echo "Process exited during sampling" >>"${scenario_dir}/errors.log"
      break
    fi
    local ts
    ts=$(date +%s)
    local cpu
    cpu=$(ps -o %cpu= -p "${pid}" | tr -d ' ')
    echo "${ts},${cpu}" >>"${cpu_csv}"
    sleep 2
  done

  if [[ -f "${diag_csv}" ]]; then
    cp "${diag_csv}" "${scenario_dir}/diagnostics.csv"
  fi

  kill "${pid}" 2>/dev/null || true
  osascript -e "tell application id \"${BUNDLE_ID}\" to quit" 2>/dev/null || true
  sleep 2
  kill "${log_pid}" 2>/dev/null || true
}

for scenario in "${scenarios[@]}"; do
  name="${scenario%%:*}"
  flags="${scenario#*:}"
  run_scenario "${name}" "${flags}"
done

python3 "${ROOT_DIR}/scripts/parse_cpu_csv.py" "${RUN_ROOT}" || true

echo "Completed run at ${RUN_ROOT}"
