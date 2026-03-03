#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DECRYPTOR="$PROJECT_ROOT/tools/validation/decrypt-installer-state.sh"
LOG_FILE=""
SUCCESS_MARKER=""

usage() {
  printf 'Usage: %s <state-file> <passphrase> <module-slug> [--dry-run]\n' "$(basename "$0")" >&2
  exit 1
}

log() {
  printf '[uninstall-module.sh] %s\n' "$1"

  if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    printf '[uninstall-module.sh] %s\n' "$1" >> "$LOG_FILE"
  fi
}

require_file() {
  local file_path="$1"

  if [ ! -f "$file_path" ]; then
    printf '[uninstall-module.sh] Missing required file: %s\n' "$file_path" >&2
    exit 1
  fi
}

remove_path() {
  local path="$1"

  [ -n "$path" ] || return
  [ -e "$path" ] || return

  rm -rf "$path"
  log "Removed $path"
}

STATE_FILE="${1:-}"
PASSPHRASE="${2:-}"
MODULE_SLUG="${3:-}"
DRY_RUN=0

[ -n "$STATE_FILE" ] || usage
[ -n "$PASSPHRASE" ] || usage
[ -n "$MODULE_SLUG" ] || usage

if [ "${4:-}" = "--dry-run" ]; then
  DRY_RUN=1
elif [ -n "${4:-}" ]; then
  usage
fi

require_file "$DECRYPTOR"
require_file "$STATE_FILE"

STATE_JSON="$(bash "$DECRYPTOR" "$STATE_FILE" "$PASSPHRASE")"
APP_ROOT="$(printf '%s' "$STATE_JSON" | jq -r '.app_root // empty')"
[ -n "$APP_ROOT" ] || { printf '[uninstall-module.sh] app_root missing in state.\n' >&2; exit 1; }

LOG_FILE="$APP_ROOT/installer/modules/logs/uninstall-module.log"
SUCCESS_MARKER="$APP_ROOT/installer/modules/last-success/uninstall-module.success"

BACKEND_TARGET="$APP_ROOT/current/modules/$MODULE_SLUG"
FRONTEND_TARGET="$APP_ROOT/public/modules/$MODULE_SLUG"
MODULE_STATE_DIR="$APP_ROOT/installer/modules/installed/$MODULE_SLUG"
MODULE_STATE_FILE="$MODULE_STATE_DIR/module-state.json"

if [ ! -f "$MODULE_STATE_FILE" ] && [ "$DRY_RUN" -eq 0 ]; then
  printf '[uninstall-module.sh] Missing module state: %s\n' "$MODULE_STATE_FILE" >&2
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  log "Dry-run: would write module uninstall log to $LOG_FILE"
  log "Dry-run: would write module uninstall success marker to $SUCCESS_MARKER"
  log "Dry-run: would remove backend module path $BACKEND_TARGET"
  log "Dry-run: would remove frontend module path $FRONTEND_TARGET"
  log "Dry-run: would remove module state $MODULE_STATE_DIR"
  exit 0
fi

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$SUCCESS_MARKER")"
: > "$LOG_FILE"
log "Initialized module uninstall log file"

remove_path "$BACKEND_TARGET"
remove_path "$FRONTEND_TARGET"
remove_path "$MODULE_STATE_DIR"

if [ -f "$APP_ROOT/current/artisan" ]; then
  (
    cd "$APP_ROOT/current"
    php artisan optimize:clear || true
  )
  log "Triggered artisan optimize:clear after module uninstall"
fi

printf 'uninstalled_at_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$SUCCESS_MARKER"
printf 'module=%s\n' "$MODULE_SLUG" >> "$SUCCESS_MARKER"
log "Wrote module uninstall success marker"

log "Module uninstall completed for $MODULE_SLUG"
