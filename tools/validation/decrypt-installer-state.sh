#!/usr/bin/env bash

set -eu

if [ "$#" -ne 2 ]; then
  printf 'Usage: %s <state-file> <passphrase>\n' "$(basename "$0")" >&2
  exit 1
fi

state_file="$1"
passphrase="$2"

if [ ! -f "$state_file" ]; then
  printf 'State file not found: %s\n' "$state_file" >&2
  exit 1
fi

STATE_FILE="$state_file" STATE_PASSPHRASE="$passphrase" php -r '
  $stateFile = getenv("STATE_FILE");
  $passphrase = getenv("STATE_PASSPHRASE");
  $envelope = json_decode(file_get_contents($stateFile), true);

  if (!is_array($envelope)) {
      fwrite(STDERR, "Invalid state envelope.\n");
      exit(1);
  }

  foreach (["salt", "iv", "payload", "iterations"] as $required) {
      if (!array_key_exists($required, $envelope)) {
          fwrite(STDERR, "Missing field: {$required}\n");
          exit(1);
      }
  }

  $salt = base64_decode($envelope["salt"], true);
  $iv = base64_decode($envelope["iv"], true);
  $payload = base64_decode($envelope["payload"], true);

  if ($salt === false || $iv === false || $payload === false) {
      fwrite(STDERR, "Invalid base64 data in state file.\n");
      exit(1);
  }

  $key = hash_pbkdf2("sha256", $passphrase, $salt, (int) $envelope["iterations"], 32, true);
  $plaintext = openssl_decrypt($payload, "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);

  if ($plaintext === false) {
      fwrite(STDERR, "Unable to decrypt state file.\n");
      exit(1);
  }

  echo $plaintext;
'
