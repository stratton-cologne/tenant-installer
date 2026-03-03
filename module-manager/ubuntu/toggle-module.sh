#!/usr/bin/env bash

set -eu

LOG_FILE=""

usage() {
  printf 'Usage: %s <app-root> <module-slug> <enable|disable>\n' "$(basename "$0")" >&2
  exit 1
}

log() {
  printf '[toggle-module.sh] %s\n' "$1"

  if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    printf '[toggle-module.sh] %s\n' "$1" >> "$LOG_FILE"
  fi
}

APP_ROOT="${1:-}"
MODULE_SLUG="${2:-}"
ACTION="${3:-}"

[ -n "$APP_ROOT" ] || usage
[ -n "$MODULE_SLUG" ] || usage
[ -n "$ACTION" ] || usage

case "$ACTION" in
  enable|disable)
    ;;
  *)
    usage
    ;;
esac

STATE_FILE="$APP_ROOT/installer/modules/installed/$MODULE_SLUG/module-state.json"
[ -f "$STATE_FILE" ] || { printf '[toggle-module.sh] Missing module state: %s\n' "$STATE_FILE" >&2; exit 1; }
LOG_FILE="$APP_ROOT/installer/modules/logs/toggle-module.log"

mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"
log "Initialized module toggle log file"

ENABLED_VALUE=false
[ "$ACTION" = "enable" ] && ENABLED_VALUE=true

tmp_state="$(mktemp)"
jq ".enabled = $ENABLED_VALUE | .updated_at_utc = (now | todate)" "$STATE_FILE" > "$tmp_state"
mv "$tmp_state" "$STATE_FILE"

log "Module $MODULE_SLUG set to $ACTION"
