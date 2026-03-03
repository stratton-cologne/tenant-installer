#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/install-module.sh"
DECRYPTOR="$(cd "$SCRIPT_DIR/../.." && pwd)/tools/validation/decrypt-installer-state.sh"
LOG_FILE=""

usage() {
  printf 'Usage: %s <state-file> <passphrase> <module-zip> [--dry-run]\n' "$(basename "$0")" >&2
  exit 1
}

STATE_FILE="${1:-}"
PASSPHRASE="${2:-}"
MODULE_ZIP="${3:-}"

[ -n "$STATE_FILE" ] || usage
[ -n "$PASSPHRASE" ] || usage
[ -n "$MODULE_ZIP" ] || usage

if [ ! -x "$INSTALL_SCRIPT" ]; then
  printf '[update-module.sh] Missing executable install script: %s\n' "$INSTALL_SCRIPT" >&2
  exit 1
fi

log() {
  printf '[update-module.sh] %s\n' "$1"

  if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    printf '[update-module.sh] %s\n' "$1" >> "$LOG_FILE"
  fi
}

if [ ! -f "$DECRYPTOR" ]; then
  printf '[update-module.sh] Missing decryptor script: %s\n' "$DECRYPTOR" >&2
  exit 1
fi

APP_ROOT="$(bash "$DECRYPTOR" "$STATE_FILE" "$PASSPHRASE" | jq -r '.app_root // empty')"
[ -n "$APP_ROOT" ] || { printf '[update-module.sh] app_root missing in state.\n' >&2; exit 1; }

LOG_FILE="$APP_ROOT/installer/modules/logs/update-module.log"
mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"
log "Initialized module update log file"

log "Delegating module update to install flow"

if [ "${4:-}" = "--dry-run" ]; then
  bash "$INSTALL_SCRIPT" "$STATE_FILE" "$PASSPHRASE" "$MODULE_ZIP" --dry-run
elif [ -n "${4:-}" ]; then
  usage
else
  bash "$INSTALL_SCRIPT" "$STATE_FILE" "$PASSPHRASE" "$MODULE_ZIP"
fi

log "Module update flow completed"
