#!/usr/bin/env bash

set -eu

if [ "$#" -ne 3 ]; then
  printf 'Usage: %s <manifest.json> <asset-base-url> <staging-directory>\n' "$(basename "$0")" >&2
  exit 1
fi

manifest_path="$1"
asset_base_url="$2"
staging_dir="$3"

if [ ! -f "$manifest_path" ]; then
  printf 'Manifest not found: %s\n' "$manifest_path" >&2
  exit 1
fi

if [ -z "$asset_base_url" ]; then
  printf 'Asset base URL is required.\n' >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'jq is required for release fetching.\n' >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  printf 'curl is required for release fetching.\n' >&2
  exit 1
fi

hash_command() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
    return
  fi

  printf 'No sha256 tool available (need sha256sum or shasum).\n' >&2
  exit 1
}

file_name="$(jq -r '.artifact.file_name // empty' "$manifest_path")"
expected_sha256="$(jq -r '.artifact.sha256 // empty' "$manifest_path")"

[ -n "$file_name" ] || { printf 'Manifest missing artifact.file_name.\n' >&2; exit 1; }
[ -n "$expected_sha256" ] || { printf 'Manifest missing artifact.sha256.\n' >&2; exit 1; }

mkdir -p "$staging_dir"
target_path="$staging_dir/$file_name"
asset_url="${asset_base_url%/}/$file_name"

curl --fail --location --silent --show-error --output "$target_path" "$asset_url"

actual_sha256="$(hash_command "$target_path")"
if [ "$actual_sha256" != "$expected_sha256" ]; then
  printf 'Downloaded artifact checksum mismatch for %s\n' "$asset_url" >&2
  printf 'Expected: %s\n' "$expected_sha256" >&2
  printf 'Actual:   %s\n' "$actual_sha256" >&2
  exit 1
fi

printf '%s\n' "$target_path"
