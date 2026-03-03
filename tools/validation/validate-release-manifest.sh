#!/usr/bin/env bash

set -eu

if [ "$#" -ne 1 ]; then
  printf 'Usage: %s <manifest.json>\n' "$(basename "$0")" >&2
  exit 1
fi

manifest_path="$1"

if [ ! -f "$manifest_path" ]; then
  printf 'Manifest not found: %s\n' "$manifest_path" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'jq is required for manifest validation.\n' >&2
  exit 1
fi

component="$(jq -r '.component // empty' "$manifest_path")"
version="$(jq -r '.version // empty' "$manifest_path")"
channel="$(jq -r '.release_channel // empty' "$manifest_path")"
sha256="$(jq -r '.artifact.sha256 // empty' "$manifest_path")"
file_name="$(jq -r '.artifact.file_name // empty' "$manifest_path")"

fail() {
  printf 'Invalid manifest: %s\n' "$1" >&2
  exit 1
}

[ -n "$component" ] || fail 'component is required'
[ -n "$version" ] || fail 'version is required'
[ -n "$channel" ] || fail 'release_channel is required'
[ -n "$file_name" ] || fail 'artifact.file_name is required'

printf '%s' "$version" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\+[0-9A-Za-z.-]+)?$' \
  || fail 'version must be stable semver without pre-release suffix'

[ "$channel" = "stable" ] || fail 'release_channel must be stable'

printf '%s' "$sha256" | grep -Eq '^[a-fA-F0-9]{64}$' \
  || fail 'artifact.sha256 must be a 64 character hexadecimal hash'

printf 'Manifest valid: component=%s version=%s file=%s\n' "$component" "$version" "$file_name"
