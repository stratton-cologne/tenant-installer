#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DECRYPTOR="$PROJECT_ROOT/tools/validation/decrypt-installer-state.sh"

DRY_RUN=0
LOG_FILE=""
SUCCESS_MARKER=""

log() {
  printf '[repair.sh] %s\n' "$1"

  if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    printf '[repair.sh] %s\n' "$1" >> "$LOG_FILE"
  fi
}

usage() {
  printf 'Usage: %s <state-file> <passphrase> [--dry-run]\n' "$(basename "$0")" >&2
  exit 1
}

require_file() {
  local file_path="$1"

  if [ ! -f "$file_path" ]; then
    printf '[repair.sh] Missing required file: %s\n' "$file_path" >&2
    exit 1
  fi
}

parse_args() {
  if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    usage
  fi

  STATE_FILE="$1"
  PASSPHRASE="$2"
  shift 2

  if [ "$#" -eq 1 ]; then
    [ "$1" = "--dry-run" ] || usage
    DRY_RUN=1
  fi
}

load_state() {
  require_file "$DECRYPTOR"
  STATE_JSON="$(bash "$DECRYPTOR" "$STATE_FILE" "$PASSPHRASE")"
}

state_get() {
  local path="$1"
  printf '%s' "$STATE_JSON" | jq -r "$path"
}

copy_directory_contents() {
  local source_dir="$1"
  local target_dir="$2"

  mkdir -p "$target_dir"
  cp -R "$source_dir"/. "$target_dir"/
}

repair_backend() {
  local current_dir release_dir

  current_dir="$(state_get '.deployed.current_release_dir // empty')"
  release_dir="$(state_get '.deployed.backend_release_dir // empty')"

  if [ -z "$current_dir" ] || [ -z "$release_dir" ]; then
    log "Backend paths missing in state; skipping backend repair"
    return
  fi

  if [ -d "$current_dir" ]; then
    log "Backend current release present: $current_dir"
    return
  fi

  if [ ! -d "$release_dir" ]; then
    log "Backend release source missing: $release_dir"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would restore backend from $release_dir to $current_dir"
    return
  fi

  copy_directory_contents "$release_dir" "$current_dir"
  log "Restored backend release into $current_dir"
}

repair_frontend() {
  local public_dir release_dir

  public_dir="$(state_get '.deployed.frontend_public_dir // empty')"
  release_dir="$(state_get '.deployed.frontend_release_dir // empty')"

  if [ -z "$public_dir" ] || [ -z "$release_dir" ]; then
    log "Frontend paths missing in state; skipping frontend repair"
    return
  fi

  if [ -d "$public_dir" ] && [ -n "$(find "$public_dir" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; then
    log "Frontend public directory present: $public_dir"
    return
  fi

  if [ ! -d "$release_dir" ]; then
    log "Frontend release source missing: $release_dir"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would restore frontend from $release_dir to $public_dir"
    return
  fi

  copy_directory_contents "$release_dir" "$public_dir"
  log "Restored frontend release into $public_dir"
}

repair_runtime() {
  local runtime_dir current_dir

  runtime_dir="$(state_get '.services.runtime_config_dir // empty')"
  current_dir="$(state_get '.deployed.current_release_dir // empty')"

  if [ -z "$runtime_dir" ]; then
    log "Runtime config path missing in state; skipping runtime repair"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would ensure runtime config directories under $runtime_dir"
    [ -n "$current_dir" ] && log "Dry-run: would restore .env from $runtime_dir/tenant.env to $current_dir/.env when needed"
    return
  fi

  mkdir -p "$runtime_dir/nginx" "$runtime_dir/systemd" "$runtime_dir/supervisor"

  if [ -n "$current_dir" ] && [ ! -f "$current_dir/.env" ] && [ -f "$runtime_dir/tenant.env" ]; then
    cp "$runtime_dir/tenant.env" "$current_dir/.env"
    log "Restored .env into $current_dir/.env"
  fi

  log "Ensured runtime directories under $runtime_dir"
}

main() {
  parse_args "$@"
  load_state
  LOG_FILE="$(state_get '.app_root // empty')/installer/logs/repair.log"
  SUCCESS_MARKER="$(state_get '.app_root // empty')/installer/state/repair.success"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would write repair log to $LOG_FILE"
    log "Dry-run: would write repair success marker to $SUCCESS_MARKER"
  else
    mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$SUCCESS_MARKER")"
    : > "$LOG_FILE"
    log "Initialized repair log file"
  fi

  repair_backend
  repair_frontend
  repair_runtime

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would mark repair success at $SUCCESS_MARKER"
  else
    printf 'repaired_at_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$SUCCESS_MARKER"
    log "Wrote repair success marker"
  fi

  log "Repair flow completed"
}

main "$@"
