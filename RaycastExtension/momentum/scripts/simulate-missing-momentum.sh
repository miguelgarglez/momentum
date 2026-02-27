#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTENSION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$EXTENSION_DIR/../.." && pwd)"

STATE_DIR="$HOME/Library/Caches/momentum-raycast"
STATE_FILE="$STATE_DIR/missing-app-state.env"

RELEASE_BUNDLE_ID="miguelgarglez.Momentum"
DEV_BUNDLE_ID="miguelgarglez.Momentum.dev"
PROCESS_PATTERN='Momentum.app(.quarantined)?/Contents/MacOS/Momentum'
LSREGISTER_BIN="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
QUARANTINED_SUFFIX=".quarantined"
DISABLED_MACOS_DIR="MacOS.__momentum_disabled__"

SEARCH_ROOTS=(
  "/Applications"
  "$HOME/Applications"
  "$HOME/.Trash"
  "$HOME/Library/Developer/Xcode/DerivedData"
  "$HOME/Library/Developer/Xcode/Archives"
  "$REPO_ROOT/.derivedData"
  "$REPO_ROOT/build/archives"
  "/private/tmp"
)

print_usage() {
  cat <<USAGE
Usage: $(basename "$0") <setup|verify|restore|status|purge>

Commands:
  setup    Move discovered Momentum.app bundles into a quarantine folder.
  verify   Check if Momentum is undiscoverable for launch (returns non-zero when discoverable).
  restore  Restore quarantined Momentum.app bundles to original paths.
  status   Show active simulation status and current verification report.
  purge    Destructively delete discovered Momentum.app bundles (no restore).
USAGE
}

load_state() {
  ACTIVE="0"
  QUARANTINE_PATH=""
  CREATED_AT=""

  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
}

write_state() {
  local quarantine_path="$1"
  mkdir -p "$STATE_DIR"
  cat >"$STATE_FILE" <<STATE
ACTIVE=1
QUARANTINE_PATH='$quarantine_path'
CREATED_AT='$(date -u +%Y-%m-%dT%H:%M:%SZ)'
STATE
}

list_found_apps() {
  local root
  for root in "${SEARCH_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    if [[ "$root" == "/private/tmp" ]]; then
      find "$root" -maxdepth 5 -type d -name "Momentum.app" 2>/dev/null || true
    else
      find "$root" -type d -name "Momentum.app" 2>/dev/null || true
    fi
  done | awk '!seen[$0]++'
}

stop_running_momentum() {
  if pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; then
    pkill -f "$PROCESS_PATTERN" || true
  fi
}

register_bundle_if_possible() {
  local app_path="$1"
  if [[ -x "$LSREGISTER_BIN" ]]; then
    "$LSREGISTER_BIN" -f "$app_path" >/dev/null 2>&1 || true
  fi
}

disable_quarantined_bundle() {
  local bundle_path="$1"
  local contents_dir="$bundle_path/Contents"
  local macos_dir="$contents_dir/MacOS"
  local disabled_dir="$contents_dir/$DISABLED_MACOS_DIR"

  [[ -d "$contents_dir" ]] || return 0

  if [[ -d "$macos_dir" && ! -d "$disabled_dir" ]]; then
    mv "$macos_dir" "$disabled_dir"
  fi
}

enable_quarantined_bundle() {
  local bundle_path="$1"
  local contents_dir="$bundle_path/Contents"
  local macos_dir="$contents_dir/MacOS"
  local disabled_dir="$contents_dir/$DISABLED_MACOS_DIR"

  [[ -d "$contents_dir" ]] || return 0

  if [[ -d "$disabled_dir" && ! -d "$macos_dir" ]]; then
    mv "$disabled_dir" "$macos_dir"
  fi
}

run_verify() {
  local release_status="NOT_FOUND"
  local dev_status="NOT_FOUND"
  local name_status="NOT_FOUND"
  local process_status="NOT_RUNNING"
  local physical_paths=()
  local physical_count=0

  while IFS= read -r app_path; do
    [[ -n "$app_path" ]] || continue
    physical_paths+=("$app_path")
    physical_count=$((physical_count + 1))
  done < <(list_found_apps)

  if open -Rb "$RELEASE_BUNDLE_ID" >/dev/null 2>&1; then
    release_status="FOUND"
  fi

  if open -Rb "$DEV_BUNDLE_ID" >/dev/null 2>&1; then
    dev_status="FOUND"
  fi

  if open -Ra "Momentum" >/dev/null 2>&1; then
    name_status="FOUND"
  fi

  if pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; then
    process_status="RUNNING"
  fi

  echo "release_bundle: $release_status"
  echo "dev_bundle:     $dev_status"
  echo "app_name:       $name_status"
  echo "process:        $process_status"
  echo "physical_apps:  $physical_count"

  if [[ "$physical_count" -eq 0 && ( "$release_status" == "FOUND" || "$dev_status" == "FOUND" || "$name_status" == "FOUND" ) ]]; then
    echo "note: LaunchServices cache may still report FOUND for bundle lookups."
  fi

  if [[ "$process_status" == "NOT_RUNNING" && "$physical_count" -eq 0 ]]; then
    echo "result: PASS (Momentum unavailable simulation is active)"
    return 0
  fi

  echo "result: FAIL (Momentum is still available)"
  if [[ "$physical_count" -gt 0 ]]; then
    echo "discovered_paths:"
    printf '%s\n' "${physical_paths[@]}" | sed 's#^#- #'
  fi
  return 1
}

setup() {
  load_state
  if [[ "$ACTIVE" == "1" && -n "$QUARANTINE_PATH" && -d "$QUARANTINE_PATH" ]]; then
    echo "Simulation already active. Run restore first."
    echo "State file: $STATE_FILE"
    exit 1
  fi

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local quarantine_path="$STATE_DIR/quarantine-$timestamp"

  mkdir -p "$quarantine_path"
  stop_running_momentum

  local moved_count=0
  local failed_moves=0
  local app_path
  while IFS= read -r app_path; do
    [[ -n "$app_path" ]] || continue
    local destination="$quarantine_path$app_path$QUARANTINED_SUFFIX"
    mkdir -p "$(dirname "$destination")"
    if mv "$app_path" "$destination"; then
      disable_quarantined_bundle "$destination" || true
      moved_count=$((moved_count + 1))
    else
      echo "Failed to quarantine: $app_path"
      failed_moves=$((failed_moves + 1))
    fi
  done < <(list_found_apps)

  write_state "$quarantine_path"

  echo "Quarantine path: $quarantine_path"
  echo "Moved apps: $moved_count"
  echo "Failed moves: $failed_moves"
  echo "Next: npm run simulate:no-app:verify"
}

restore() {
  load_state
  stop_running_momentum

  if [[ "$ACTIVE" != "1" || -z "$QUARANTINE_PATH" ]]; then
    echo "No active simulation state found."
    exit 0
  fi

  if [[ ! -d "$QUARANTINE_PATH" ]]; then
    echo "Quarantine folder not found: $QUARANTINE_PATH"
    rm -f "$STATE_FILE"
    echo "Stale state file cleared."
    exit 0
  fi

  local restored_count=0
  local skipped_count=0
  local failed_count=0
  local moved_path

  while IFS= read -r moved_path; do
    [[ -n "$moved_path" ]] || continue

    local original_path="${moved_path#"$QUARANTINE_PATH"}"
    original_path="${original_path%$QUARANTINED_SUFFIX}"
    if [[ "$original_path" == "$moved_path" || -z "$original_path" ]]; then
      skipped_count=$((skipped_count + 1))
      continue
    fi

    if [[ -e "$original_path" ]]; then
      echo "Skipping existing destination: $original_path"
      skipped_count=$((skipped_count + 1))
      continue
    fi

    mkdir -p "$(dirname "$original_path")"
    enable_quarantined_bundle "$moved_path" || true
    if mv "$moved_path" "$original_path"; then
      register_bundle_if_possible "$original_path"
      restored_count=$((restored_count + 1))
    else
      echo "Failed to restore: $moved_path"
      failed_count=$((failed_count + 1))
    fi
  done < <(
    find "$QUARANTINE_PATH" \( -type d -name "Momentum.app$QUARANTINED_SUFFIX" -o -type d -name "Momentum.app" \) 2>/dev/null | sort
  )

  local remaining
  if [[ -d "$QUARANTINE_PATH" ]]; then
    find "$QUARANTINE_PATH" -depth -type d -empty -delete 2>/dev/null || true
    if [[ -d "$QUARANTINE_PATH" ]]; then
      remaining="$(find "$QUARANTINE_PATH" \( -type d -name "Momentum.app$QUARANTINED_SUFFIX" -o -type d -name "Momentum.app" \) 2>/dev/null | wc -l | tr -d ' ')"
    else
      remaining="0"
    fi
  else
    remaining="0"
  fi

  echo "Restored apps: $restored_count"
  echo "Skipped apps: $skipped_count"
  echo "Failed restores: $failed_count"

  if [[ "$remaining" == "0" && "$failed_count" == "0" ]]; then
    rm -rf "$QUARANTINE_PATH"
    rm -f "$STATE_FILE"
    echo "Simulation state cleared."
    return 0
  fi

  echo "Some app bundles remain in quarantine: $remaining"
  echo "Run status for details."
  return 1
}

status() {
  load_state

  echo "state_file: $STATE_FILE"
  if [[ "$ACTIVE" == "1" && -n "$QUARANTINE_PATH" ]]; then
    echo "active: yes"
    echo "quarantine_path: $QUARANTINE_PATH"
    echo "created_at_utc: ${CREATED_AT:-unknown}"

    if [[ -d "$QUARANTINE_PATH" ]]; then
      local quarantined
      quarantined="$(find "$QUARANTINE_PATH" \( -type d -name "Momentum.app$QUARANTINED_SUFFIX" -o -type d -name "Momentum.app" \) 2>/dev/null | wc -l | tr -d ' ')"
      echo "quarantined_apps: $quarantined"
    else
      echo "quarantined_apps: 0 (quarantine path missing)"
      rm -f "$STATE_FILE"
      echo "stale_state: cleared"
    fi
  else
    echo "active: no"
  fi

  echo
  run_verify || true
}

purge() {
  load_state
  stop_running_momentum

  local deleted_count=0
  local failed_count=0
  local app_path

  while IFS= read -r app_path; do
    [[ -n "$app_path" ]] || continue
    if rm -rf "$app_path"; then
      deleted_count=$((deleted_count + 1))
    else
      echo "Failed to delete: $app_path"
      failed_count=$((failed_count + 1))
    fi
  done < <(list_found_apps)

  if [[ "$ACTIVE" == "1" && -n "$QUARANTINE_PATH" && -d "$QUARANTINE_PATH" ]]; then
    while IFS= read -r app_path; do
      [[ -n "$app_path" ]] || continue
      if rm -rf "$app_path"; then
        deleted_count=$((deleted_count + 1))
      else
        echo "Failed to delete quarantined app: $app_path"
        failed_count=$((failed_count + 1))
      fi
    done < <(
      find "$QUARANTINE_PATH" \( -type d -name "Momentum.app$QUARANTINED_SUFFIX" -o -type d -name "Momentum.app" \) 2>/dev/null
    )
    find "$QUARANTINE_PATH" -depth -type d -empty -delete 2>/dev/null || true
  fi

  rm -f "$STATE_FILE"

  echo "Deleted app bundles: $deleted_count"
  echo "Failed deletions: $failed_count"
  echo "Purge is destructive. Rebuild Momentum to restore app bundles."
  run_verify || true

  if [[ "$failed_count" -gt 0 ]]; then
    return 1
  fi
}

case "${1:-}" in
  setup)
    setup
    ;;
  verify)
    run_verify
    ;;
  restore)
    restore
    ;;
  status)
    status
    ;;
  purge)
    purge
    ;;
  *)
    print_usage
    exit 1
    ;;
esac
