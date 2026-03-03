#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PREFLIGHT_SCRIPT="$SCRIPT_DIR/preflight.sh"
ENV_TEMPLATE="$PROJECT_ROOT/shared/templates/tenant.env.tpl"
NGINX_TEMPLATE="$PROJECT_ROOT/shared/templates/nginx-tenant-site.conf.tpl"
SYSTEMD_QUEUE_TEMPLATE="$PROJECT_ROOT/shared/templates/systemd-queue-worker.service.tpl"
SYSTEMD_SCHEDULER_SERVICE_TEMPLATE="$PROJECT_ROOT/shared/templates/systemd-scheduler.service.tpl"
SYSTEMD_SCHEDULER_TIMER_TEMPLATE="$PROJECT_ROOT/shared/templates/systemd-scheduler.timer.tpl"
SUPERVISOR_QUEUE_TEMPLATE="$PROJECT_ROOT/shared/templates/supervisor-queue-worker.conf.tpl"
MANIFEST_DIR="$PROJECT_ROOT/shared/manifests"
RELEASE_SELECTOR="$PROJECT_ROOT/tools/release/select-latest-stable.sh"
ARTIFACT_STAGER="$PROJECT_ROOT/tools/release/stage-local-artifact.sh"
REMOTE_ARTIFACT_FETCHER="$PROJECT_ROOT/tools/release/fetch-release-asset.sh"
LOCAL_ARTIFACT_DIR="$PROJECT_ROOT/artifacts"
ASSET_SOURCE="${ASSET_SOURCE:-local}"
ASSET_BASE_URL="${ASSET_BASE_URL:-}"

CHECK_ONLY=0
DRY_RUN=0

APP_ROOT=""
DOMAIN=""
USE_SSL=""
DB_HOST=""
DB_PORT=""
DB_DATABASE=""
DB_USERNAME=""
DB_PASSWORD=""
ADMIN_EMAIL=""
ADMIN_PASSWORD=""
ENABLE_SMTP=""
MAIL_HOST=""
MAIL_PORT=""
MAIL_USERNAME=""
MAIL_PASSWORD=""
MAIL_ENCRYPTION=""
MAIL_FROM_ADDRESS=""
TENANT_ID=""
LICENSE_KEY=""
RUN_SEEDERS=""
BACKEND_MANIFEST=""
FRONTEND_MANIFEST=""
BACKEND_VERSION=""
FRONTEND_VERSION=""
INSTALLATION_ID=""
STATE_PATH=""
BACKEND_ARTIFACT=""
FRONTEND_ARTIFACT=""
BACKEND_RELEASE_DIR=""
FRONTEND_RELEASE_DIR=""
CURRENT_RELEASE_DIR=""
RUNTIME_CONFIG_DIR=""
FRONTEND_PUBLIC_DIR=""
BOOTSTRAP_STATUS="pending"
LOG_FILE=""
SUCCESS_MARKER=""

log() {
  printf '[install.sh] %s\n' "$1"

  if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    printf '[install.sh] %s\n' "$1" >> "$LOG_FILE"
  fi
}

require_file() {
  local file_path="$1"

  if [ ! -f "$file_path" ]; then
    printf '[install.sh] Missing required file: %s\n' "$file_path" >&2
    exit 1
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --check)
        CHECK_ONLY=1
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      *)
        printf '[install.sh] Unknown argument: %s\n' "$1" >&2
        exit 1
        ;;
    esac
    shift
  done
}

run_preflight() {
  require_file "$PREFLIGHT_SCRIPT"
  log "Running preflight checks"
  "$PREFLIGHT_SCRIPT"
}

resolve_local_release_manifest() {
  local component="$1"

  require_file "$RELEASE_SELECTOR"
  "$RELEASE_SELECTOR" "$MANIFEST_DIR" "$component"
}

stage_local_artifact() {
  local manifest_path="$1"
  local staging_dir="$2"

  require_file "$ARTIFACT_STAGER"
  bash "$ARTIFACT_STAGER" "$manifest_path" "$LOCAL_ARTIFACT_DIR" "$staging_dir"
}

fetch_remote_artifact() {
  local manifest_path="$1"
  local staging_dir="$2"

  require_file "$REMOTE_ARTIFACT_FETCHER"
  bash "$REMOTE_ARTIFACT_FETCHER" "$manifest_path" "$ASSET_BASE_URL" "$staging_dir"
}

prompt_value() {
  local variable_name="$1"
  local label="$2"
  local default_value="${3:-}"
  local input_value=""

  if [ -n "$default_value" ]; then
    printf '%s [%s]: ' "$label" "$default_value"
  else
    printf '%s: ' "$label"
  fi

  IFS= read -r input_value

  if [ -z "$input_value" ]; then
    input_value="$default_value"
  fi

  printf -v "$variable_name" '%s' "$input_value"
}

prompt_secret() {
  local variable_name="$1"
  local label="$2"
  local input_value=""

  printf '%s: ' "$label"
  stty -echo
  IFS= read -r input_value
  stty echo
  printf '\n'

  printf -v "$variable_name" '%s' "$input_value"
}

prompt_yes_no() {
  local variable_name="$1"
  local label="$2"
  local default_value="$3"
  local input_value=""

  while :; do
    printf '%s [%s]: ' "$label" "$default_value"
    IFS= read -r input_value

    if [ -z "$input_value" ]; then
      input_value="$default_value"
    fi

    case "$input_value" in
      y|Y|yes|YES)
        printf -v "$variable_name" 'yes'
        return
        ;;
      n|N|no|NO)
        printf -v "$variable_name" 'no'
        return
        ;;
    esac

    printf '[install.sh] Please answer yes or no.\n'
  done
}

collect_input() {
  log "Collecting interactive input"

  prompt_value APP_ROOT "Application root directory" "/var/www/tenant-platform"
  prompt_value DOMAIN "Primary domain" ""
  prompt_yes_no USE_SSL "Enable SSL" "yes"
  prompt_value ADMIN_EMAIL "Admin email" ""
  prompt_secret ADMIN_PASSWORD "Admin password"

  prompt_value DB_HOST "Database host" "127.0.0.1"
  prompt_value DB_PORT "Database port" "3306"
  prompt_value DB_DATABASE "Database name" "tenant_platform"
  prompt_value DB_USERNAME "Database user" "tenant_user"
  prompt_secret DB_PASSWORD "Database password"

  prompt_yes_no ENABLE_SMTP "Configure SMTP" "no"

  if [ "$ENABLE_SMTP" = "yes" ]; then
    prompt_value MAIL_HOST "SMTP host" ""
    prompt_value MAIL_PORT "SMTP port" "587"
    prompt_value MAIL_USERNAME "SMTP username" ""
    prompt_secret MAIL_PASSWORD "SMTP password"
    prompt_value MAIL_ENCRYPTION "SMTP encryption" "tls"
    prompt_value MAIL_FROM_ADDRESS "Mail from address" "$ADMIN_EMAIL"
  else
    MAIL_HOST=""
    MAIL_PORT=""
    MAIL_USERNAME=""
    MAIL_PASSWORD=""
    MAIL_ENCRYPTION=""
    MAIL_FROM_ADDRESS="${ADMIN_EMAIL:-noreply@example.com}"
  fi

  prompt_value TENANT_ID "Tenant ID (optional)" ""
  prompt_value LICENSE_KEY "License key (optional)" ""
  prompt_yes_no RUN_SEEDERS "Run database seeders after migrations" "no"
}

ensure_required_values() {
  [ -n "$DOMAIN" ] || { printf '[install.sh] Domain is required.\n' >&2; exit 1; }
  [ -n "$ADMIN_EMAIL" ] || { printf '[install.sh] Admin email is required.\n' >&2; exit 1; }
  [ -n "$ADMIN_PASSWORD" ] || { printf '[install.sh] Admin password is required.\n' >&2; exit 1; }
  [ -n "$DB_PASSWORD" ] || { printf '[install.sh] Database password is required.\n' >&2; exit 1; }
}

init_run_artifacts() {
  LOG_FILE="$APP_ROOT/installer/logs/install.log"
  SUCCESS_MARKER="$APP_ROOT/installer/state/install.success"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would write installer log to $LOG_FILE"
    log "Dry-run: would write success marker to $SUCCESS_MARKER"
    return
  fi

  mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$SUCCESS_MARKER")"
  : > "$LOG_FILE"
  log "Initialized install log file"
}

escape_template_value() {
  printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

generate_app_key() {
  php -r 'echo "base64:".base64_encode(random_bytes(32));'
}

generate_hex_secret() {
  php -r 'echo bin2hex(random_bytes(32));'
}

render_template() {
  local template_path="$1"
  local output_path="$2"
  local rendered
  local app_scheme="http"
  local mail_mailer="log"
  local mail_host="$MAIL_HOST"
  local mail_port="$MAIL_PORT"
  local mail_username="$MAIL_USERNAME"
  local mail_password="$MAIL_PASSWORD"
  local mail_encryption="$MAIL_ENCRYPTION"
  local mail_from_address="$MAIL_FROM_ADDRESS"
  local app_key
  local jwt_secret

  [ "$USE_SSL" = "yes" ] && app_scheme="https"
  [ "$ENABLE_SMTP" = "yes" ] && mail_mailer="smtp"

  app_key="$(generate_app_key)"
  jwt_secret="$(generate_hex_secret)"

  rendered="$(cat "$template_path")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{APP_KEY}}/$(escape_template_value "$app_key")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{APP_URL}}/$(escape_template_value "$app_scheme://$DOMAIN")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{TENANT_PORTAL_URL}}/$(escape_template_value "$app_scheme://$DOMAIN")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{DB_HOST}}/$(escape_template_value "$DB_HOST")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{DB_PORT}}/$(escape_template_value "$DB_PORT")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{DB_DATABASE}}/$(escape_template_value "$DB_DATABASE")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{DB_USERNAME}}/$(escape_template_value "$DB_USERNAME")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{DB_PASSWORD}}/$(escape_template_value "$DB_PASSWORD")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{MAIL_MAILER}}/$(escape_template_value "$mail_mailer")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{MAIL_HOST}}/$(escape_template_value "$mail_host")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{MAIL_PORT}}/$(escape_template_value "$mail_port")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{MAIL_USERNAME}}/$(escape_template_value "$mail_username")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{MAIL_PASSWORD}}/$(escape_template_value "$mail_password")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{MAIL_ENCRYPTION}}/$(escape_template_value "$mail_encryption")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{MAIL_FROM_ADDRESS}}/$(escape_template_value "$mail_from_address")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{LICENSE_API_URL}}//g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{CORE_API_TOKEN}}//g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{CORE_TO_TENANT_SYNC_TOKEN}}//g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{AUTO_LICENSE_SYNC_ENABLED}}/false/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{E2E_CORE_TENANT_UUID}}/$(escape_template_value "$TENANT_ID")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{JWT_SECRET}}/$(escape_template_value "$jwt_secret")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{SERVER_NAME}}/$(escape_template_value "$DOMAIN")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s#{{APP_ROOT}}#$(escape_template_value "$APP_ROOT")#g")"
  rendered="$(printf '%s' "$rendered" | sed "s#{{APP_PUBLIC_ROOT}}#$(escape_template_value "$APP_ROOT/public")#g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{APP_USER}}/$(escape_template_value "www-data")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s/{{APP_GROUP}}/$(escape_template_value "www-data")/g")"
  rendered="$(printf '%s' "$rendered" | sed "s#{{PHP_BIN}}#$(escape_template_value "/usr/bin/php")#g")"
  rendered="$(printf '%s' "$rendered" | sed "s#{{PHP_FPM_SOCKET}}#$(escape_template_value "/run/php/php8.2-fpm.sock")#g")"
  rendered="$(printf '%s' "$rendered" | sed "s#{{LOG_DIR}}#$(escape_template_value "$APP_ROOT/storage/logs")#g")"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run preview for $(basename "$output_path")"
    printf '%s\n' "$rendered"
    return
  fi

  mkdir -p "$(dirname "$output_path")"
  printf '%s\n' "$rendered" > "$output_path"
  log "Generated $(basename "$output_path")"
}

render_generated_files() {
  local generated_dir="$APP_ROOT/installer/generated"

  require_file "$ENV_TEMPLATE"
  require_file "$NGINX_TEMPLATE"
  require_file "$SYSTEMD_QUEUE_TEMPLATE"
  require_file "$SYSTEMD_SCHEDULER_SERVICE_TEMPLATE"
  require_file "$SYSTEMD_SCHEDULER_TIMER_TEMPLATE"
  require_file "$SUPERVISOR_QUEUE_TEMPLATE"

  log "Rendering configuration files"
  render_template "$ENV_TEMPLATE" "$generated_dir/tenant.env"
  render_template "$NGINX_TEMPLATE" "$generated_dir/nginx-site.conf"
  render_template "$SYSTEMD_QUEUE_TEMPLATE" "$generated_dir/systemd/tenant-queue-worker.service"
  render_template "$SYSTEMD_SCHEDULER_SERVICE_TEMPLATE" "$generated_dir/systemd/tenant-scheduler.service"
  render_template "$SYSTEMD_SCHEDULER_TIMER_TEMPLATE" "$generated_dir/systemd/tenant-scheduler.timer"
  render_template "$SUPERVISOR_QUEUE_TEMPLATE" "$generated_dir/supervisor/tenant-queue-worker.conf"
}

resolve_release_manifests() {
  require_file "$RELEASE_SELECTOR"

  log "Resolving latest stable local release manifests"
  BACKEND_MANIFEST="$(resolve_local_release_manifest tenant-backend)"
  FRONTEND_MANIFEST="$(resolve_local_release_manifest tenant-frontend)"
  BACKEND_VERSION="$(jq -r '.version' "$BACKEND_MANIFEST")"
  FRONTEND_VERSION="$(jq -r '.version' "$FRONTEND_MANIFEST")"

  log "Selected backend manifest: $(basename "$BACKEND_MANIFEST") (version $BACKEND_VERSION)"
  log "Selected frontend manifest: $(basename "$FRONTEND_MANIFEST") (version $FRONTEND_VERSION)"
}

generate_installation_id() {
  php -r 'echo bin2hex(random_bytes(16));'
}

encrypt_payload_to_file() {
  local output_path="$1"

  STATE_PASSPHRASE="$ADMIN_PASSWORD" php -r '
    $payload = stream_get_contents(STDIN);
    $passphrase = getenv("STATE_PASSPHRASE");

    if ($passphrase === false || $passphrase == "") {
        fwrite(STDERR, "Missing encryption passphrase.\n");
        exit(1);
    }

    $salt = random_bytes(32);
    $iv = random_bytes(16);
    $key = hash_pbkdf2("sha256", $passphrase, $salt, 100000, 32, true);
    $ciphertext = openssl_encrypt($payload, "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);

    if ($ciphertext === false) {
        fwrite(STDERR, "State encryption failed.\n");
        exit(1);
    }

    echo json_encode(
        [
            "version" => "1",
            "cipher" => "AES-256-CBC",
            "kdf" => "PBKDF2-SHA256",
            "iterations" => 100000,
            "salt" => base64_encode($salt),
            "iv" => base64_encode($iv),
            "payload" => base64_encode($ciphertext)
        ],
        JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES
    );
  ' > "$output_path"
}

persist_installer_state() {
  local state_dir="$APP_ROOT/installer/state"
  local backend_version="$BACKEND_VERSION"
  local frontend_version="$FRONTEND_VERSION"
  local state_json

  INSTALLATION_ID="$(generate_installation_id)"
  STATE_PATH="$state_dir/install-state.enc.json"

  state_json="$(
    INSTALLATION_ID="$INSTALLATION_ID" \
    APP_ROOT="$APP_ROOT" \
    STATE_PATH="$STATE_PATH" \
    BACKEND_VERSION="$backend_version" \
    FRONTEND_VERSION="$frontend_version" \
    BACKEND_ARTIFACT="$BACKEND_ARTIFACT" \
    FRONTEND_ARTIFACT="$FRONTEND_ARTIFACT" \
    BACKEND_RELEASE_DIR="$BACKEND_RELEASE_DIR" \
    FRONTEND_RELEASE_DIR="$FRONTEND_RELEASE_DIR" \
    CURRENT_RELEASE_DIR="$CURRENT_RELEASE_DIR" \
    RUNTIME_CONFIG_DIR="$RUNTIME_CONFIG_DIR" \
    FRONTEND_PUBLIC_DIR="$FRONTEND_PUBLIC_DIR" \
    BOOTSTRAP_STATUS="$BOOTSTRAP_STATUS" \
    DB_HOST="$DB_HOST" \
    DB_PORT="$DB_PORT" \
    DB_DATABASE="$DB_DATABASE" \
    php -r '
      echo json_encode(
          [
              "schema_version" => "1.0.0",
              "installation_id" => getenv("INSTALLATION_ID"),
              "platform" => "ubuntu",
              "app_root" => getenv("APP_ROOT"),
              "state_file" => [
                  "path" => getenv("STATE_PATH"),
                  "encrypted" => true
              ],
              "deployed" => [
                  "backend_version" => getenv("BACKEND_VERSION"),
                  "frontend_version" => getenv("FRONTEND_VERSION"),
                  "backend_artifact" => getenv("BACKEND_ARTIFACT"),
                  "frontend_artifact" => getenv("FRONTEND_ARTIFACT"),
                  "backend_release_dir" => getenv("BACKEND_RELEASE_DIR"),
                  "frontend_release_dir" => getenv("FRONTEND_RELEASE_DIR"),
                  "current_release_dir" => getenv("CURRENT_RELEASE_DIR"),
                  "frontend_public_dir" => getenv("FRONTEND_PUBLIC_DIR"),
                  "bootstrap_status" => getenv("BOOTSTRAP_STATUS"),
                  "modules" => []
              ],
              "services" => [
                  "web_server" => "nginx",
                  "scheduler" => "tenant-scheduler.timer",
                  "queue_worker" => "tenant-queue-worker",
                  "runtime_config_dir" => getenv("RUNTIME_CONFIG_DIR")
              ],
              "database" => [
                  "engine" => "mysql",
                  "host" => getenv("DB_HOST"),
                  "port" => (int) getenv("DB_PORT"),
                  "name" => getenv("DB_DATABASE"),
                  "managed_by_installer" => false
              ],
              "timestamps" => [
                  "installed_at_utc" => gmdate("c")
              ]
          ],
          JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES
      );
    '
  )"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run preview for installer state metadata"
    printf '%s\n' "$state_json"
    return
  fi

  mkdir -p "$state_dir"
  printf '%s' "$state_json" | encrypt_payload_to_file "$STATE_PATH"
  chmod 600 "$STATE_PATH"
  log "Persisted encrypted installer state to $STATE_PATH"
}

stage_release_artifacts() {
  local cache_dir="$APP_ROOT/installer/cache"
  local backend_file
  local frontend_file

  backend_file="$(jq -r '.artifact.file_name' "$BACKEND_MANIFEST")"
  frontend_file="$(jq -r '.artifact.file_name' "$FRONTEND_MANIFEST")"

  if [ "$DRY_RUN" -eq 1 ]; then
    BACKEND_ARTIFACT="$cache_dir/$backend_file"
    FRONTEND_ARTIFACT="$cache_dir/$frontend_file"
    log "Dry-run: would stage backend artifact to $BACKEND_ARTIFACT"
    log "Dry-run: would stage frontend artifact to $FRONTEND_ARTIFACT"
    return
  fi

  if [ "$ASSET_SOURCE" = "remote" ]; then
    log "Fetching release artifacts from $ASSET_BASE_URL"
    BACKEND_ARTIFACT="$(fetch_remote_artifact "$BACKEND_MANIFEST" "$cache_dir")"
    FRONTEND_ARTIFACT="$(fetch_remote_artifact "$FRONTEND_MANIFEST" "$cache_dir")"
  else
    log "Staging release artifacts from $LOCAL_ARTIFACT_DIR"
    BACKEND_ARTIFACT="$(stage_local_artifact "$BACKEND_MANIFEST" "$cache_dir")"
    FRONTEND_ARTIFACT="$(stage_local_artifact "$FRONTEND_MANIFEST" "$cache_dir")"
  fi

  log "Staged backend artifact: $BACKEND_ARTIFACT"
  log "Staged frontend artifact: $FRONTEND_ARTIFACT"
}

extract_release_artifacts() {
  local releases_root="$APP_ROOT/releases"
  local backend_target="$releases_root/backend-$BACKEND_VERSION"
  local frontend_target="$releases_root/frontend-$FRONTEND_VERSION"

  if [ "$DRY_RUN" -eq 1 ]; then
    BACKEND_RELEASE_DIR="$backend_target"
    FRONTEND_RELEASE_DIR="$frontend_target"
    log "Dry-run: would extract backend artifact to $BACKEND_RELEASE_DIR"
    log "Dry-run: would extract frontend artifact to $FRONTEND_RELEASE_DIR"
    return
  fi

  mkdir -p "$backend_target" "$frontend_target"
  unzip -oq "$BACKEND_ARTIFACT" -d "$backend_target"
  unzip -oq "$FRONTEND_ARTIFACT" -d "$frontend_target"

  BACKEND_RELEASE_DIR="$backend_target"
  FRONTEND_RELEASE_DIR="$frontend_target"

  log "Extracted backend artifact to $BACKEND_RELEASE_DIR"
  log "Extracted frontend artifact to $FRONTEND_RELEASE_DIR"
}

copy_directory_contents() {
  local source_dir="$1"
  local target_dir="$2"

  mkdir -p "$target_dir"
  cp -R "$source_dir"/. "$target_dir"/
}

deploy_backend_release() {
  local current_dir="$APP_ROOT/current"

  if [ "$DRY_RUN" -eq 1 ]; then
    CURRENT_RELEASE_DIR="$current_dir"
    log "Dry-run: would deploy backend release into $CURRENT_RELEASE_DIR"
    return
  fi

  mkdir -p "$current_dir"
  copy_directory_contents "$BACKEND_RELEASE_DIR" "$current_dir"

  CURRENT_RELEASE_DIR="$current_dir"
  log "Deployed backend release into $CURRENT_RELEASE_DIR"
}

deploy_frontend_release() {
  local public_dir="$APP_ROOT/public"
  local frontend_source="$FRONTEND_RELEASE_DIR"
  local backup_dir="$APP_ROOT/backups/frontend-$FRONTEND_VERSION"

  if [ "$DRY_RUN" -eq 1 ]; then
    FRONTEND_PUBLIC_DIR="$public_dir"
    log "Dry-run: would deploy frontend release into $FRONTEND_PUBLIC_DIR"
    return
  fi

  mkdir -p "$public_dir"

  if [ -d "$public_dir" ] && [ -n "$(find "$public_dir" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; then
    mkdir -p "$backup_dir"
    copy_directory_contents "$public_dir" "$backup_dir"
    log "Backed up existing public assets to $backup_dir"
  fi

  find "$public_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  copy_directory_contents "$frontend_source" "$public_dir"

  FRONTEND_PUBLIC_DIR="$public_dir"
  log "Deployed frontend release into $FRONTEND_PUBLIC_DIR"
}

deploy_runtime_configs() {
  local generated_dir="$APP_ROOT/installer/generated"
  local runtime_dir="$APP_ROOT/runtime"

  if [ "$DRY_RUN" -eq 1 ]; then
    RUNTIME_CONFIG_DIR="$runtime_dir"
    log "Dry-run: would deploy runtime configs into $RUNTIME_CONFIG_DIR"
    return
  fi

  mkdir -p "$runtime_dir/nginx" "$runtime_dir/systemd" "$runtime_dir/supervisor"

  cp "$generated_dir/tenant.env" "$APP_ROOT/current/.env"
  cp "$generated_dir/tenant.env" "$runtime_dir/tenant.env"
  cp "$generated_dir/nginx-site.conf" "$runtime_dir/nginx/tenant-site.conf"
  cp "$generated_dir/systemd/tenant-queue-worker.service" "$runtime_dir/systemd/tenant-queue-worker.service"
  cp "$generated_dir/systemd/tenant-scheduler.service" "$runtime_dir/systemd/tenant-scheduler.service"
  cp "$generated_dir/systemd/tenant-scheduler.timer" "$runtime_dir/systemd/tenant-scheduler.timer"
  cp "$generated_dir/supervisor/tenant-queue-worker.conf" "$runtime_dir/supervisor/tenant-queue-worker.conf"

  RUNTIME_CONFIG_DIR="$runtime_dir"
  log "Deployed runtime config set into $RUNTIME_CONFIG_DIR"
}

deploy_application_layout() {
  deploy_backend_release
  deploy_frontend_release
  deploy_runtime_configs
}

run_in_current_release() {
  local command_string="$1"

  if [ -z "$CURRENT_RELEASE_DIR" ]; then
    printf '[install.sh] Current release directory is not available.\n' >&2
    exit 1
  fi

  (
    cd "$CURRENT_RELEASE_DIR"
    /bin/sh -c "$command_string"
  )
}

bootstrap_laravel_app() {
  local php_bin="/usr/bin/php"
  local composer_cmd="composer install --no-interaction --prefer-dist --optimize-autoloader"
  local migrate_cmd="$php_bin artisan migrate --force"
  local seed_cmd="$php_bin artisan db:seed --force"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would run in $CURRENT_RELEASE_DIR -> $composer_cmd"
    log "Dry-run: would run in $CURRENT_RELEASE_DIR -> $php_bin artisan key:generate --force"
    log "Dry-run: would run in $CURRENT_RELEASE_DIR -> $migrate_cmd"
    if [ "$RUN_SEEDERS" = "yes" ]; then
      log "Dry-run: would run in $CURRENT_RELEASE_DIR -> $seed_cmd"
    fi
    BOOTSTRAP_STATUS="dry-run"
    return
  fi

  if [ ! -f "$CURRENT_RELEASE_DIR/artisan" ]; then
    log "Skipping Laravel bootstrap because artisan is missing in $CURRENT_RELEASE_DIR"
    BOOTSTRAP_STATUS="skipped-missing-artisan"
    return
  fi

  log "Running composer install in $CURRENT_RELEASE_DIR"
  run_in_current_release "$composer_cmd"

  log "Generating application key"
  run_in_current_release "$php_bin artisan key:generate --force"

  log "Running database migrations"
  run_in_current_release "$migrate_cmd"

  if [ "$RUN_SEEDERS" = "yes" ]; then
    log "Running database seeders"
    run_in_current_release "$seed_cmd"
  fi

  BOOTSTRAP_STATUS="completed"
  log "Laravel bootstrap completed"
}

show_next_steps() {
  cat <<EOF
[install.sh] Configuration stage completed.
[install.sh] Next implementation steps:
[install.sh] 1. Activate nginx, systemd and supervisor configs on the target system.
[install.sh] 2. Run service reloads and health checks.
[install.sh] 3. Finalize installer logs and success markers.
EOF
}

write_success_marker() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would mark install success at $SUCCESS_MARKER"
    return
  fi

  printf 'installed_at_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$SUCCESS_MARKER"
  printf 'backend_version=%s\n' "$BACKEND_VERSION" >> "$SUCCESS_MARKER"
  printf 'frontend_version=%s\n' "$FRONTEND_VERSION" >> "$SUCCESS_MARKER"
  log "Wrote install success marker"
}

main() {
  parse_args "$@"
  log "Starting Ubuntu install flow"
  log "Project root: $PROJECT_ROOT"
  run_preflight

  if [ "$CHECK_ONLY" -eq 1 ]; then
    log "Check-only mode requested; stopping after preflight"
    exit 0
  fi

  collect_input
  ensure_required_values
  init_run_artifacts
  resolve_release_manifests
  render_generated_files
  stage_release_artifacts
  extract_release_artifacts
  deploy_application_layout
  bootstrap_laravel_app
  persist_installer_state
  write_success_marker
  show_next_steps
}

main "$@"
