#!/usr/bin/env bash

set -u

SCRIPT_NAME="$(basename "$0")"
CHECK_MODE="check"
EXIT_CODE=0

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$1"
}

pass() {
  printf '[PASS] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1"
  EXIT_CODE=1
}

check_command() {
  local command_name="$1"
  local required="$2"

  if command -v "$command_name" >/dev/null 2>&1; then
    pass "Befehl verfuegbar: $command_name"
  elif [ "$required" = "required" ]; then
    fail "Befehl fehlt: $command_name"
  else
    warn "Optionaler Befehl fehlt: $command_name"
  fi
}

check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    pass "Ausfuehrung mit Root-Rechten"
  else
    fail "Root-Rechte sind erforderlich"
  fi
}

check_os() {
  if [ ! -r /etc/os-release ]; then
    fail "/etc/os-release ist nicht lesbar"
    return
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  if [ "${ID:-}" != "ubuntu" ]; then
    fail "Nicht unterstuetztes Betriebssystem: ${ID:-unbekannt}"
    return
  fi

  if [ -z "${VERSION_ID:-}" ]; then
    fail "Ubuntu-Version konnte nicht ermittelt werden"
    return
  fi

  if dpkg --compare-versions "$VERSION_ID" ge "22.04"; then
    pass "Unterstuetzte Ubuntu-Version erkannt: $VERSION_ID"
  else
    fail "Ubuntu $VERSION_ID ist kleiner als 22.04"
  fi
}

check_php() {
  if ! command -v php >/dev/null 2>&1; then
    fail "PHP fehlt"
    return
  fi

  local php_version
  php_version="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)"

  if [ "$php_version" = "8.2" ]; then
    pass "PHP 8.2 erkannt"
  else
    fail "Falsche PHP-Version erkannt: ${php_version:-unbekannt} (erwartet 8.2)"
  fi
}

check_php_extensions() {
  local missing=0
  local extensions="pdo_mysql mbstring openssl xml curl zip"
  local extension

  for extension in $extensions; do
    if php -m 2>/dev/null | grep -qi "^${extension}$"; then
      pass "PHP-Extension verfuegbar: $extension"
    else
      fail "PHP-Extension fehlt: $extension"
      missing=1
    fi
  done

  return "$missing"
}

check_ports() {
  local port
  for port in 80 443; do
    if command -v ss >/dev/null 2>&1 && ss -ltn "( sport = :$port )" 2>/dev/null | grep -q ":$port"; then
      warn "Port $port ist bereits belegt"
    else
      pass "Port $port ist aktuell frei oder nicht eindeutig belegt"
    fi
  done
}

main() {
  log "Starte Preflight-Pruefung im Modus: $CHECK_MODE"

  check_root
  check_os
  check_command nginx optional
  check_command composer required
  check_command jq required
  check_command unzip required
  check_command curl optional
  check_command mysql optional
  check_command mariadb optional
  check_command certbot optional
  check_command dig optional
  check_php
  check_php_extensions
  check_ports

  if [ "$EXIT_CODE" -eq 0 ]; then
    log "Preflight erfolgreich abgeschlossen"
  else
    log "Preflight mit Fehlern abgeschlossen"
  fi

  exit "$EXIT_CODE"
}

main "$@"
