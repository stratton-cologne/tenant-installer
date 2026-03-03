#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DECRYPTOR="$PROJECT_ROOT/tools/validation/decrypt-installer-state.sh"

APPLY_CHANGES=0
LOG_FILE=""
SUCCESS_MARKER=""

log() {
  printf '[activate-runtime.sh] %s\n' "$1"

  if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    printf '[activate-runtime.sh] %s\n' "$1" >> "$LOG_FILE"
  fi
}

usage() {
  printf 'Usage: %s <state-file> <passphrase> [--apply]\n' "$(basename "$0")" >&2
  exit 1
}

require_file() {
  local file_path="$1"

  if [ ! -f "$file_path" ]; then
    printf '[activate-runtime.sh] Missing required file: %s\n' "$file_path" >&2
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
    [ "$1" = "--apply" ] || usage
    APPLY_CHANGES=1
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

copy_if_apply() {
  local source_file="$1"
  local target_file="$2"

  if [ "$APPLY_CHANGES" -eq 0 ]; then
    log "Would copy $source_file -> $target_file"
    return
  fi

  mkdir -p "$(dirname "$target_file")"
  cp "$source_file" "$target_file"
  log "Copied $source_file -> $target_file"
}

reload_if_apply() {
  local command_string="$1"

  if [ "$APPLY_CHANGES" -eq 0 ]; then
    log "Would run: $command_string"
    return
  fi

  /bin/sh -c "$command_string"
  log "Ran: $command_string"
}

main() {
  local runtime_dir current_dir
  local nginx_source systemd_queue_source systemd_scheduler_source systemd_timer_source supervisor_source
  local nginx_target systemd_queue_target systemd_scheduler_target systemd_timer_target supervisor_target

  parse_args "$@"
  load_state

  runtime_dir="$(state_get '.services.runtime_config_dir // empty')"
  current_dir="$(state_get '.deployed.current_release_dir // empty')"

  [ -n "$runtime_dir" ] || { printf '[activate-runtime.sh] runtime_config_dir missing in state.\n' >&2; exit 1; }
  [ -n "$current_dir" ] || { printf '[activate-runtime.sh] current_release_dir missing in state.\n' >&2; exit 1; }

  LOG_FILE="$(state_get '.app_root // empty')/installer/logs/activate-runtime.log"
  SUCCESS_MARKER="$(state_get '.app_root // empty')/installer/state/activate-runtime.success"

  nginx_source="$runtime_dir/nginx/tenant-site.conf"
  systemd_queue_source="$runtime_dir/systemd/tenant-queue-worker.service"
  systemd_scheduler_source="$runtime_dir/systemd/tenant-scheduler.service"
  systemd_timer_source="$runtime_dir/systemd/tenant-scheduler.timer"
  supervisor_source="$runtime_dir/supervisor/tenant-queue-worker.conf"

  require_file "$nginx_source"
  require_file "$systemd_queue_source"
  require_file "$systemd_scheduler_source"
  require_file "$systemd_timer_source"
  require_file "$supervisor_source"

  nginx_target="/etc/nginx/sites-available/tenant-site.conf"
  systemd_queue_target="/etc/systemd/system/tenant-queue-worker.service"
  systemd_scheduler_target="/etc/systemd/system/tenant-scheduler.service"
  systemd_timer_target="/etc/systemd/system/tenant-scheduler.timer"
  supervisor_target="/etc/supervisor/conf.d/tenant-queue-worker.conf"

  if [ "$APPLY_CHANGES" -eq 0 ]; then
    log "Preview mode: would write runtime activation log to $LOG_FILE"
    log "Preview mode: would write success marker to $SUCCESS_MARKER"
  else
    mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$SUCCESS_MARKER")"
    : > "$LOG_FILE"
    log "Initialized runtime activation log file"
  fi

  log "Current release: $current_dir"
  copy_if_apply "$nginx_source" "$nginx_target"
  copy_if_apply "$systemd_queue_source" "$systemd_queue_target"
  copy_if_apply "$systemd_scheduler_source" "$systemd_scheduler_target"
  copy_if_apply "$systemd_timer_source" "$systemd_timer_target"
  copy_if_apply "$supervisor_source" "$supervisor_target"

  reload_if_apply "systemctl daemon-reload"
  reload_if_apply "systemctl enable tenant-queue-worker.service tenant-scheduler.timer"
  reload_if_apply "systemctl restart tenant-queue-worker.service tenant-scheduler.timer"
  reload_if_apply "systemctl restart nginx"
  reload_if_apply "supervisorctl reread && supervisorctl update"

  if [ "$APPLY_CHANGES" -eq 0 ]; then
    log "Preview completed. Re-run with --apply to activate runtime configs."
  else
    printf 'activated_at_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$SUCCESS_MARKER"
    printf 'runtime_dir=%s\n' "$runtime_dir" >> "$SUCCESS_MARKER"
    log "Wrote runtime activation success marker"
    log "Runtime activation completed"
  fi
}

main "$@"
