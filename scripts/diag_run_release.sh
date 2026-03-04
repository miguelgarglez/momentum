#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="${BUNDLE_ID:-miguelgarglez.Momentum}"
APP_NAME="${APP_NAME:-Momentum}"
WARMUP_S="${WARMUP_S:-30}"
CPU_SAMPLE_S="${CPU_SAMPLE_S:-360}"
CPU_SAMPLE_INTERVAL_S="${CPU_SAMPLE_INTERVAL_S:-2}"
TIMEPROFILER_S="${TIMEPROFILER_S:-60}"
SCENARIO_DRIVER_PATH="${SCENARIO_DRIVER_PATH:-}"
DIAG_FORCE_ACTIVE="${DIAG_FORCE_ACTIVE:-1}"
DIAG_PRESEED="${DIAG_PRESEED:-1}"
DIAG_UI="${DIAG_UI:-1}"
DIAG_UI_INTERVAL_S="${DIAG_UI_INTERVAL_S:-6}"

read_pref_or_missing() {
  local key="$1"
  local value
  value="$(defaults read "${BUNDLE_ID}" "${key}" 2>/dev/null || true)"
  if [[ -z "${value}" ]]; then
    echo "__MISSING__"
  else
    echo "${value}"
  fi
}

restore_float_pref() {
  local key="$1"
  local value="$2"
  if [[ "${value}" == "__MISSING__" ]]; then
    defaults delete "${BUNDLE_ID}" "${key}" >/dev/null 2>&1 || true
    return
  fi
  defaults write "${BUNDLE_ID}" "${key}" -float "${value}" >/dev/null 2>&1 || true
}

restore_bool_pref() {
  local key="$1"
  local value="$2"
  if [[ "${value}" == "__MISSING__" ]]; then
    defaults delete "${BUNDLE_ID}" "${key}" >/dev/null 2>&1 || true
    return
  fi
  case "${value}" in
    1|true|TRUE|yes|YES|on|ON)
      defaults write "${BUNDLE_ID}" "${key}" -bool true >/dev/null 2>&1 || true
      ;;
    *)
      defaults write "${BUNDLE_ID}" "${key}" -bool false >/dev/null 2>&1 || true
      ;;
  esac
}

ORIGINAL_DETECTION_INTERVAL="$(read_pref_or_missing "tracker.detectionInterval")"
ORIGINAL_IDLE_THRESHOLD="$(read_pref_or_missing "tracker.idleThreshold")"
ORIGINAL_TRACK_DOMAINS="$(read_pref_or_missing "tracker.trackDomains")"
ORIGINAL_TRACK_FILES="$(read_pref_or_missing "tracker.trackFiles")"
TRACKER_DEFAULTS_RESTORED=0

restore_tracker_defaults() {
  if [[ "${TRACKER_DEFAULTS_RESTORED}" == "1" ]]; then
    return
  fi
  TRACKER_DEFAULTS_RESTORED=1
  restore_float_pref "tracker.detectionInterval" "${ORIGINAL_DETECTION_INTERVAL}"
  restore_float_pref "tracker.idleThreshold" "${ORIGINAL_IDLE_THRESHOLD}"
  restore_bool_pref "tracker.trackDomains" "${ORIGINAL_TRACK_DOMAINS}"
  restore_bool_pref "tracker.trackFiles" "${ORIGINAL_TRACK_FILES}"
}

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

scenarios_all=(
  "baseline:"
  "disable_idle_check:DISABLE_IDLE_CHECK=1"
  "disable_heartbeat:DISABLE_HEARTBEAT=1"
  "disable_budget_monitor:DISABLE_BUDGET_MONITOR=1"
  "disable_backfill:DISABLE_BACKFILL=1"
  "disable_crash_recovery:DISABLE_CRASH_RECOVERY=1"
  "disable_swiftdata_writes:DISABLE_SWIFTDATA_WRITES=1"
  "disable_overlay_updates:DISABLE_OVERLAY_UPDATES=1"
)

if [[ -n "${SCENARIOS:-}" ]]; then
  IFS=',' read -r -a requested <<< "${SCENARIOS}"
  scenarios=()
  for req in "${requested[@]}"; do
    req="${req// /}"
    found=false
    for scenario in "${scenarios_all[@]}"; do
      name="${scenario%%:*}"
      if [[ "${name}" == "${req}" ]]; then
        scenarios+=("${scenario}")
        found=true
        break
      fi
    done
    if [[ "${found}" == "false" ]]; then
      echo "Unknown scenario: ${req}" >&2
      exit 1
    fi
  done
else
  scenarios=("${scenarios_all[@]}")
fi

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
- warmup_s: ${WARMUP_S}
- cpu_sample_s: ${CPU_SAMPLE_S}
- cpu_sample_interval_s: ${CPU_SAMPLE_INTERVAL_S}
- timeprofiler_s: ${TIMEPROFILER_S}
- scenario_driver_path: ${SCENARIO_DRIVER_PATH:-none}
- diag_force_active: ${DIAG_FORCE_ACTIVE}
- diag_preseed: ${DIAG_PRESEED}
- diag_ui: ${DIAG_UI}
- diag_ui_interval_s: ${DIAG_UI_INTERVAL_S}
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

format_duration() {
  local total_s="$1"
  local minutes=$((total_s / 60))
  local seconds=$((total_s % 60))
  printf "%dm %ds" "${minutes}" "${seconds}"
}

TOTAL_DURATION_S=0

cleanup_after_signal() {
  if [[ -n "${ACTIVE_DRIVER_PID:-}" ]]; then
    kill "${ACTIVE_DRIVER_PID}" 2>/dev/null || true
  fi
  if [[ -n "${ACTIVE_APP_PID:-}" ]]; then
    kill "${ACTIVE_APP_PID}" 2>/dev/null || true
  fi
  if [[ -n "${ACTIVE_LOG_PID:-}" ]]; then
    kill "${ACTIVE_LOG_PID}" 2>/dev/null || true
  fi
  osascript -e "tell application id \"${BUNDLE_ID}\" to quit" 2>/dev/null || true
  osascript -e "tell application \"Safari\" to quit" 2>/dev/null || true
  osascript -e "tell application \"Preview\" to quit" 2>/dev/null || true
}

trap cleanup_after_signal INT TERM
trap restore_tracker_defaults EXIT

run_scenario() {
  local name="$1"
  local flags="$2"
  local index="$3"
  local total="$4"
  local scenario_start_ts
  scenario_start_ts=$(date +%s)
  local scenario_dir="${RUN_ROOT}/${name}"
  mkdir -p "${scenario_dir}"

  echo "Running scenario ${index}/${total}: ${name}"

  osascript -e "tell application id \"${BUNDLE_ID}\" to quit" 2>/dev/null || true
  sleep 2

  defaults write "${BUNDLE_ID}" tracker.idleThreshold -float 99999 >/dev/null 2>&1 || true
  defaults write "${BUNDLE_ID}" tracker.detectionInterval -float 1 >/dev/null 2>&1 || true
  defaults write "${BUNDLE_ID}" tracker.trackDomains -bool true >/dev/null 2>&1 || true
  defaults write "${BUNDLE_ID}" tracker.trackFiles -bool true >/dev/null 2>&1 || true

  local diag_csv="${HOME}/Library/Logs/Momentum/diagnostics.csv"
  rm -f "${diag_csv}"

  local store_root="${HOME}/Library/Containers/${BUNDLE_ID}/Data/Library/Application Support/MomentumDiagnostics/${TIMESTAMP}"
  local store_dir="${store_root}/${name}"
  rm -rf "${store_dir}"
  mkdir -p "${store_dir}"

  if [[ "${DIAG_PRESEED}" == "1" ]]; then
    local seed_stdout="${scenario_dir}/preseed_stdout.log"
    local seed_stderr="${scenario_dir}/preseed_stderr.log"
    local seed_errors="${scenario_dir}/errors.log"
    set +u
    env MOM_DIAG_PRESEED=1 \
      MOMENTUM_SKIP_ONBOARDING=1 \
      MOMENTUM_STORE_PATH="${store_dir}" \
      "${APP_EXEC}" --seed-diagnostics-store --skip-debug-seed >"${seed_stdout}" 2>"${seed_stderr}" &
    local seed_pid=$!
    set -u
    local waited=0
    while ps -p "${seed_pid}" >/dev/null 2>&1; do
      sleep 1
      waited=$((waited + 1))
      if [[ "${waited}" -ge 45 ]]; then
        echo "Preseed timed out for ${name}" >>"${seed_errors}"
        kill "${seed_pid}" 2>/dev/null || true
        break
      fi
    done
    wait "${seed_pid}" 2>/dev/null || true
  fi

  local log_file="${scenario_dir}/logs.txt"
  local log_cmd=(log stream --style compact --predicate "subsystem == \"${BUNDLE_ID}\"")
  if [[ "${log_supports_signpost}" == "true" ]]; then
    log_cmd+=(--signpost)
  fi
  "${log_cmd[@]}" >"${log_file}" 2>&1 &
  local log_pid=$!
  ACTIVE_LOG_PID="${log_pid}"

  # Launch app with env vars
  set +u
  env MOM_DIAG=1 \
    MOM_DIAG_SEED=1 \
    $( [[ "${DIAG_UI}" == "1" ]] && echo "MOM_DIAG_UI=1" ) \
    $( [[ "${DIAG_UI}" == "1" ]] && echo "MOM_DIAG_UI_INTERVAL_S=${DIAG_UI_INTERVAL_S}" ) \
    MOMENTUM_SKIP_ONBOARDING=1 \
    MOMENTUM_STORE_PATH="${store_dir}" \
    $( [[ "${DIAG_FORCE_ACTIVE}" == "1" ]] && echo "DISABLE_IDLE_CHECK=1" ) \
    ${flags} "${APP_EXEC}" >"${scenario_dir}/app_stdout.log" 2>"${scenario_dir}/app_stderr.log" &
  local app_pid=$!
  ACTIVE_APP_PID="${app_pid}"
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

  sleep "${WARMUP_S}"

  local driver_pid=""
  local driver_log_src="/tmp/momentum-diag/driver.log"
  local driver_stdout="${scenario_dir}/driver_stdout.log"
  if [[ -n "${SCENARIO_DRIVER_PATH}" ]]; then
    rm -f "${driver_log_src}"
    local phase_idle_s=$((CPU_SAMPLE_S * 10 / 100))
    local phase_domain_s=$((CPU_SAMPLE_S * 25 / 100))
    local phase_file_s=$((CPU_SAMPLE_S * 20 / 100))
    local phase_mixed_s=$((CPU_SAMPLE_S * 25 / 100))
    local phase_momentum_s=$((CPU_SAMPLE_S - phase_idle_s - phase_domain_s - phase_file_s - phase_mixed_s))
    DRIVER_DURATION_S="${CPU_SAMPLE_S}" \
      DRIVER_PHASE_IDLE_S="${phase_idle_s}" \
      DRIVER_PHASE_DOMAIN_S="${phase_domain_s}" \
      DRIVER_PHASE_FILE_S="${phase_file_s}" \
      DRIVER_PHASE_MIXED_S="${phase_mixed_s}" \
      DRIVER_PHASE_MOMENTUM_S="${phase_momentum_s}" \
      "${SCENARIO_DRIVER_PATH}" >"${driver_stdout}" 2>&1 &
    driver_pid=$!
    ACTIVE_DRIVER_PID="${driver_pid}"
  fi

  local cpu_csv="${scenario_dir}/cpu.csv"
  (
    echo "timestamp,cpu_percent" >"${cpu_csv}"
    local start_ts
    start_ts=$(date +%s)
    local end_ts=$((start_ts + CPU_SAMPLE_S))
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
      sleep "${CPU_SAMPLE_INTERVAL_S}"
    done
  ) &
  local cpu_pid=$!

  local trace_path="${scenario_dir}/timeprofiler.trace"
  xcrun xctrace record --template "Time Profiler" --attach "${pid}" --time-limit "${TIMEPROFILER_S}s" \
    --output "${trace_path}" >"${scenario_dir}/timeprofiler.log" 2>&1 || \
    echo "Time Profiler failed for ${name}" >>"${scenario_dir}/errors.log"

  wait "${cpu_pid}" 2>/dev/null || true

  if [[ -f "${diag_csv}" ]]; then
    cp "${diag_csv}" "${scenario_dir}/diagnostics.csv"
  fi

  if [[ -n "${driver_pid}" ]]; then
    kill "${driver_pid}" 2>/dev/null || true
    ACTIVE_DRIVER_PID=""
    if [[ -s "${driver_log_src}" ]]; then
      cp "${driver_log_src}" "${scenario_dir}/driver.log"
    elif [[ -s "${driver_stdout}" ]]; then
      cp "${driver_stdout}" "${scenario_dir}/driver.log"
    fi
  fi

  kill "${pid}" 2>/dev/null || true
  ACTIVE_APP_PID=""
  osascript -e "tell application id \"${BUNDLE_ID}\" to quit" 2>/dev/null || true
  sleep 2
  kill "${log_pid}" 2>/dev/null || true
  ACTIVE_LOG_PID=""

  local scenario_end_ts
  scenario_end_ts=$(date +%s)
  local scenario_duration_s=$((scenario_end_ts - scenario_start_ts))
  TOTAL_DURATION_S=$((TOTAL_DURATION_S + scenario_duration_s))
  echo "scenario_duration_s_${name}: ${scenario_duration_s}" >>"${RUN_INFO}"
  echo "${scenario_duration_s}" >"${scenario_dir}/duration_s.txt"
}

total_scenarios="${#scenarios[@]}"
index=1
RUN_START_TS=$(date +%s)
for scenario in "${scenarios[@]}"; do
  name="${scenario%%:*}"
  flags="${scenario#*:}"
  run_scenario "${name}" "${flags}" "${index}" "${total_scenarios}"
  index=$((index + 1))
done
RUN_END_TS=$(date +%s)
RUN_TOTAL_S=$((RUN_END_TS - RUN_START_TS))
if [[ "${RUN_TOTAL_S}" -le 0 ]]; then
  RUN_TOTAL_S="${TOTAL_DURATION_S}"
fi
AVG_SCENARIO_S=0
if [[ "${total_scenarios}" -gt 0 ]]; then
  AVG_SCENARIO_S=$((RUN_TOTAL_S / total_scenarios))
fi
{
  echo "total_duration_s: ${RUN_TOTAL_S}"
  echo "avg_scenario_duration_s: ${AVG_SCENARIO_S}"
} >>"${RUN_INFO}"

python3 "${ROOT_DIR}/scripts/parse_cpu_csv.py" "${RUN_ROOT}" || true

echo "Completed run at ${RUN_ROOT} (duration: $(format_duration "${RUN_TOTAL_S}"))"
