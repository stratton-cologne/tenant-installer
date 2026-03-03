#!/usr/bin/env bash

set -eu

if [ "$#" -ne 3 ]; then
  printf 'Usage: %s <manifest.json> <artifact-directory> <staging-directory>\n' "$(basename "$0")" >&2
  exit 1
fi

manifest_path="$1"
artifact_dir="$2"
staging_dir="$3"

if [ ! -f "$manifest_path" ]; then
  printf 'Manifest not found: %s\n' "$manifest_path" >&2
  exit 1
fi

if [ ! -d "$artifact_dir" ]; then
  printf 'Artifact directory not found: %s\n' "$artifact_dir" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'jq is required for artifact staging.\n' >&2
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

source_path="$artifact_dir/$file_name"
target_path="$staging_dir/$file_name"

if [ ! -f "$source_path" ]; then
  printf 'Artifact not found: %s\n' "$source_path" >&2
  exit 1
fi

actual_sha256="$(hash_command "$source_path")"

if [ "$actual_sha256" != "$expected_sha256" ]; then
  printf 'Artifact checksum mismatch for %s\n' "$source_path" >&2
  printf 'Expected: %s\n' "$expected_sha256" >&2
  printf 'Actual:   %s\n' "$actual_sha256" >&2
  exit 1
fi

mkdir -p "$staging_dir"
cp "$source_path" "$target_path"

printf '%s\n' "$target_path"
