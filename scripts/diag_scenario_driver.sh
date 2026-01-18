#!/usr/bin/env bash
set -euo pipefail

DURATION_S="${DRIVER_DURATION_S:-240}"
TEMP_DIR="${DRIVER_TEMP_DIR:-/tmp/momentum-diag}"
LOG_PATH="${DRIVER_LOG_PATH:-${TEMP_DIR}/driver.log}"
KEEP_AWAKE="${DRIVER_KEEP_AWAKE:-1}"

PHASE_IDLE_S="${DRIVER_PHASE_IDLE_S:-20}"
PHASE_DOMAIN_S="${DRIVER_PHASE_DOMAIN_S:-80}"
PHASE_FILE_S="${DRIVER_PHASE_FILE_S:-60}"
PHASE_MIXED_S="${DRIVER_PHASE_MIXED_S:-80}"
PHASE_MOMENTUM_S="${DRIVER_PHASE_MOMENTUM_S:-40}"

CYCLE_PAUSE_S="${DRIVER_CYCLE_PAUSE_S:-2}"
MOMENTUM_APP_NAME="${DRIVER_MOMENTUM_APP:-Momentum}"
MOMENTUM_MODE="${DRIVER_MOMENTUM_MODE:-pulse}"
MOMENTUM_FOREGROUND_S="${DRIVER_MOMENTUM_FOREGROUND_S:-20}"
MOMENTUM_BACKGROUND_APP="${DRIVER_MOMENTUM_BACKGROUND_APP:-Safari}"

URLS_RAW="${DRIVER_URLS:-https://example.com,https://developer.apple.com,https://www.wikipedia.org,https://www.mozilla.org}"
IFS=',' read -r -a URLS <<< "${URLS_RAW}"

APP_ROTATION_RAW="${DRIVER_APP_ROTATION:-Xcode,Visual Studio Code,Ghostty,Notes}"
IFS=',' read -r -a APP_ROTATION <<< "${APP_ROTATION_RAW}"

mkdir -p "${TEMP_DIR}"
> "${LOG_PATH}"

log_line() {
  echo "[$(date +"%H:%M:%S")] $*" >>"${LOG_PATH}"
}

KEEP_AWAKE_PID=""
cleanup_driver() {
  if [[ -n "${KEEP_AWAKE_PID}" ]]; then
    kill "${KEEP_AWAKE_PID}" 2>/dev/null || true
  fi
}

trap cleanup_driver INT TERM EXIT

make_pdf() {
  local name="$1"
  local txt="${TEMP_DIR}/${name}.txt"
  local pdf="${TEMP_DIR}/${name}.pdf"
  if [[ ! -f "${pdf}" ]]; then
    cat >"${txt}" <<EOF_TEXT
Momentum diagnostic file: ${name}
Generated: $(date)
EOF_TEXT
    textutil -convert pdf "${txt}" -output "${pdf}" >/dev/null 2>&1 || true
  fi
  echo "${pdf}"
}

PDF_A="$(make_pdf "momentum-diag-a")"
PDF_B="$(make_pdf "momentum-diag-b")"
PDF_C="$(make_pdf "momentum-diag-c")"
PDFS=("${PDF_A}" "${PDF_B}" "${PDF_C}")

open -a "Safari" >/dev/null 2>&1 || true
open -a "Preview" "${PDF_A}" >/dev/null 2>&1 || true
for app in "${APP_ROTATION[@]}"; do
  open -a "${app}" >/dev/null 2>&1 || true
done
sleep 2

if [[ "${KEEP_AWAKE}" == "1" ]]; then
  caffeinate -u -t "${DURATION_S}" >/dev/null 2>&1 &
  KEEP_AWAKE_PID=$!
  log_line "keep-awake enabled"
fi
log_line "momentum-mode ${MOMENTUM_MODE}"

set_url() {
  local url="$1"
  osascript -e 'tell application "Safari" to if not (exists document 1) then make new document' >/dev/null 2>&1 || true
  osascript -e "tell application \"Safari\" to set URL of front document to \"${url}\"" >/dev/null 2>&1 || true
}

activate_app() {
  local name="$1"
  osascript -e "tell application \"${name}\" to activate" >/dev/null 2>&1 || true
}

run_until() {
  local end_ts="$1"
  shift
  while [[ $(date +%s) -lt ${end_ts} ]]; do
    "$@"
  done
}

start_ts=$(date +%s)
end_ts=$((start_ts + DURATION_S))
now_ts="${start_ts}"
url_index=0
pdf_index=0
app_index=0

phase_idle() {
  sleep 2
}

phase_domain() {
  activate_app "Safari"
  if [[ ${#URLS[@]} -gt 0 ]]; then
    local url="${URLS[${url_index}]}"
    set_url "${url}"
    url_index=$(( (url_index + 1) % ${#URLS[@]} ))
  fi
  sleep 4
}

phase_file() {
  local pdf="${PDFS[${pdf_index}]}"
  open -a "Preview" "${pdf}" >/dev/null 2>&1 || true
  activate_app "Preview"
  pdf_index=$(( (pdf_index + 1) % ${#PDFS[@]} ))
  sleep 4
}

phase_mixed() {
  phase_domain
  phase_file
  if [[ ${#APP_ROTATION[@]} -gt 0 ]]; then
    local app="${APP_ROTATION[${app_index}]}"
    activate_app "${app}"
    app_index=$(( (app_index + 1) % ${#APP_ROTATION[@]} ))
  else
    activate_app "Finder"
  fi
  sleep "${CYCLE_PAUSE_S}"
}

phase_momentum() {
  case "${MOMENTUM_MODE}" in
    foreground)
      activate_app "${MOMENTUM_APP_NAME}"
      sleep "${MOMENTUM_FOREGROUND_S}"
      ;;
    pulse|*)
      activate_app "${MOMENTUM_APP_NAME}"
      sleep "${MOMENTUM_FOREGROUND_S}"
      activate_app "${MOMENTUM_BACKGROUND_APP}"
      sleep 2
      ;;
  esac
}

log_line "phase idle start"
now_ts=$((now_ts + PHASE_IDLE_S))
run_until "${now_ts}" phase_idle
log_line "phase idle end"

log_line "phase domain start"
now_ts=$((now_ts + PHASE_DOMAIN_S))
run_until "${now_ts}" phase_domain
log_line "phase domain end"

log_line "phase file start"
now_ts=$((now_ts + PHASE_FILE_S))
run_until "${now_ts}" phase_file
log_line "phase file end"

log_line "phase mixed start"
now_ts=$((now_ts + PHASE_MIXED_S))
run_until "${now_ts}" phase_mixed
log_line "phase mixed end"

log_line "phase momentum start"
now_ts=$((now_ts + PHASE_MOMENTUM_S))
run_until "${now_ts}" phase_momentum
log_line "phase momentum end"

log_line "driver finished"
