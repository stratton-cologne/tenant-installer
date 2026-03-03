#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DECRYPTOR="$PROJECT_ROOT/tools/validation/decrypt-installer-state.sh"

DRY_RUN=0
KEEP_DATA=""
LOG_FILE=""
SUCCESS_MARKER=""

log() {
  printf '[uninstall.sh] %s\n' "$1"

  if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    printf '[uninstall.sh] %s\n' "$1" >> "$LOG_FILE"
  fi
}

usage() {
  printf 'Usage: %s <state-file> <passphrase> [--dry-run]\n' "$(basename "$0")" >&2
  exit 1
}

require_file() {
  local file_path="$1"

  if [ ! -f "$file_path" ]; then
    printf '[uninstall.sh] Missing required file: %s\n' "$file_path" >&2
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

prompt_keep_data() {
  local answer=""

  while :; do
    printf 'Keep database and release files for manual recovery? [yes]: '
    IFS= read -r answer

    if [ -z "$answer" ]; then
      answer="yes"
    fi

    case "$answer" in
      y|Y|yes|YES)
        KEEP_DATA="yes"
        return
        ;;
      n|N|no|NO)
        KEEP_DATA="no"
        return
        ;;
    esac

    printf '[uninstall.sh] Please answer yes or no.\n'
  done
}

remove_path() {
  local path="$1"

  [ -n "$path" ] || return
  [ -e "$path" ] || return

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would remove $path"
    return
  fi

  rm -rf "$path"
  log "Removed $path"
}

main() {
  local app_root current_dir public_dir runtime_dir cache_dir state_file_path
  local backend_release_dir frontend_release_dir releases_root

  parse_args "$@"
  load_state
  LOG_FILE="$(state_get '.app_root // empty')/installer/logs/uninstall.log"
  SUCCESS_MARKER="$(state_get '.app_root // empty')/installer/state/uninstall.success"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would write uninstall log to $LOG_FILE"
    log "Dry-run: would write uninstall success marker to $SUCCESS_MARKER"
  else
    mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$SUCCESS_MARKER")"
    : > "$LOG_FILE"
    log "Initialized uninstall log file"
  fi

  prompt_keep_data

  app_root="$(state_get '.app_root // empty')"
  current_dir="$(state_get '.deployed.current_release_dir // empty')"
  public_dir="$(state_get '.deployed.frontend_public_dir // empty')"
  runtime_dir="$(state_get '.services.runtime_config_dir // empty')"
  state_file_path="$(state_get '.state_file.path // empty')"
  backend_release_dir="$(state_get '.deployed.backend_release_dir // empty')"
  frontend_release_dir="$(state_get '.deployed.frontend_release_dir // empty')"
  cache_dir="$app_root/installer/cache"
  releases_root="$app_root/releases"

  remove_path "$current_dir"
  remove_path "$public_dir"
  remove_path "$runtime_dir"
  remove_path "$cache_dir"

  if [ "$KEEP_DATA" = "no" ]; then
    remove_path "$backend_release_dir"
    remove_path "$frontend_release_dir"
    remove_path "$releases_root"
  else
    log "Keeping release directories for manual recovery"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would remove state file $state_file_path"
  elif [ -n "$state_file_path" ] && [ -f "$state_file_path" ]; then
    rm -f "$state_file_path"
    log "Removed $state_file_path"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would mark uninstall success at $SUCCESS_MARKER"
  else
    printf 'uninstalled_at_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$SUCCESS_MARKER"
    printf 'kept_release_data=%s\n' "$KEEP_DATA" >> "$SUCCESS_MARKER"
    log "Wrote uninstall success marker"
  fi

  log "Uninstall flow completed"
}

main "$@"
