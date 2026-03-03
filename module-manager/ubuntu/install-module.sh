#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DECRYPTOR="$PROJECT_ROOT/tools/validation/decrypt-installer-state.sh"
LOG_FILE=""
SUCCESS_MARKER=""

usage() {
  printf 'Usage: %s <state-file> <passphrase> <module-zip> [--dry-run]\n' "$(basename "$0")" >&2
  exit 1
}

log() {
  printf '[install-module.sh] %s\n' "$1"

  if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    printf '[install-module.sh] %s\n' "$1" >> "$LOG_FILE"
  fi
}

require_file() {
  local file_path="$1"

  if [ ! -f "$file_path" ]; then
    printf '[install-module.sh] Missing required file: %s\n' "$file_path" >&2
    exit 1
  fi
}

copy_directory_contents() {
  local source_dir="$1"
  local target_dir="$2"

  mkdir -p "$target_dir"
  cp -R "$source_dir"/. "$target_dir"/
}

STATE_FILE="${1:-}"
PASSPHRASE="${2:-}"
MODULE_ZIP="${3:-}"
DRY_RUN=0

[ -n "$STATE_FILE" ] || usage
[ -n "$PASSPHRASE" ] || usage
[ -n "$MODULE_ZIP" ] || usage

if [ "${4:-}" = "--dry-run" ]; then
  DRY_RUN=1
elif [ -n "${4:-}" ]; then
  usage
fi

require_file "$DECRYPTOR"
require_file "$STATE_FILE"
require_file "$MODULE_ZIP"

STATE_JSON="$(bash "$DECRYPTOR" "$STATE_FILE" "$PASSPHRASE")"
APP_ROOT="$(printf '%s' "$STATE_JSON" | jq -r '.app_root // empty')"
[ -n "$APP_ROOT" ] || { printf '[install-module.sh] app_root missing in state.\n' >&2; exit 1; }

LOG_FILE="$APP_ROOT/installer/modules/logs/install-module.log"
SUCCESS_MARKER="$APP_ROOT/installer/modules/last-success/install-module.success"

if [ "$DRY_RUN" -eq 1 ]; then
  log "Dry-run: would write module log to $LOG_FILE"
  log "Dry-run: would write module success marker to $SUCCESS_MARKER"
else
  mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$SUCCESS_MARKER")"
  : > "$LOG_FILE"
  log "Initialized module install log file"
fi

WORK_DIR="$APP_ROOT/installer/modules/tmp"
EXTRACT_DIR="$WORK_DIR/extract"

if [ "$DRY_RUN" -eq 1 ]; then
  log "Dry-run: would extract $MODULE_ZIP into $EXTRACT_DIR"
else
  rm -rf "$WORK_DIR"
  mkdir -p "$EXTRACT_DIR"
  unzip -oq "$MODULE_ZIP" -d "$EXTRACT_DIR"
fi

MODULE_MANIFEST="$EXTRACT_DIR/module.json"
if [ "$DRY_RUN" -eq 1 ]; then
  log "Dry-run: expecting module manifest at $MODULE_MANIFEST"
else
  require_file "$MODULE_MANIFEST"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  MODULE_SLUG="dry-run-module"
  MODULE_VERSION="0.0.0"
else
  MODULE_SLUG="$(jq -r '.slug // empty' "$MODULE_MANIFEST")"
  MODULE_VERSION="$(jq -r '.version // empty' "$MODULE_MANIFEST")"
fi

[ -n "$MODULE_SLUG" ] || { printf '[install-module.sh] module slug missing.\n' >&2; exit 1; }
[ -n "$MODULE_VERSION" ] || { printf '[install-module.sh] module version missing.\n' >&2; exit 1; }

BACKEND_SOURCE="$EXTRACT_DIR/backend"
FRONTEND_SOURCE="$EXTRACT_DIR/frontend"
BACKEND_TARGET="$APP_ROOT/current/modules/$MODULE_SLUG"
FRONTEND_TARGET="$APP_ROOT/public/modules/$MODULE_SLUG"
MODULE_STATE_DIR="$APP_ROOT/installer/modules/installed/$MODULE_SLUG"
MODULE_STATE_FILE="$MODULE_STATE_DIR/module-state.json"

if [ "$DRY_RUN" -eq 1 ]; then
  log "Dry-run: would install backend to $BACKEND_TARGET"
  log "Dry-run: would install frontend to $FRONTEND_TARGET"
  log "Dry-run: would persist module state to $MODULE_STATE_FILE"
  exit 0
fi

if [ -d "$BACKEND_SOURCE" ]; then
  copy_directory_contents "$BACKEND_SOURCE" "$BACKEND_TARGET"
  log "Installed backend module files into $BACKEND_TARGET"
fi

if [ -d "$FRONTEND_SOURCE" ]; then
  copy_directory_contents "$FRONTEND_SOURCE" "$FRONTEND_TARGET"
  log "Installed frontend module files into $FRONTEND_TARGET"
fi

mkdir -p "$MODULE_STATE_DIR"
cp "$MODULE_MANIFEST" "$MODULE_STATE_FILE"
tmp_state="$(mktemp)"
jq '. + {enabled: true, installed_at_utc: now | todate}' "$MODULE_STATE_FILE" > "$tmp_state"
mv "$tmp_state" "$MODULE_STATE_FILE"
log "Persisted module state to $MODULE_STATE_FILE"

if [ -f "$APP_ROOT/current/artisan" ]; then
  (
    cd "$APP_ROOT/current"
    php artisan migrate --force || true
  )
  log "Triggered artisan migrate for module install"
fi

log "Module install completed for $MODULE_SLUG@$MODULE_VERSION"

if [ "$DRY_RUN" -eq 1 ]; then
  log "Dry-run: would mark module install success at $SUCCESS_MARKER"
else
  printf 'installed_at_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$SUCCESS_MARKER"
  printf 'module=%s\n' "$MODULE_SLUG" >> "$SUCCESS_MARKER"
  printf 'version=%s\n' "$MODULE_VERSION" >> "$SUCCESS_MARKER"
  log "Wrote module install success marker"
fi
