#!/usr/bin/env bash

set -eu

if [ "$#" -ne 2 ]; then
  printf 'Usage: %s <manifest-directory> <component>\n' "$(basename "$0")" >&2
  exit 1
fi

manifest_dir="$1"
component="$2"

if [ ! -d "$manifest_dir" ]; then
  printf 'Manifest directory not found: %s\n' "$manifest_dir" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'jq is required to select release manifests.\n' >&2
  exit 1
fi

selection="$(
  find "$manifest_dir" -maxdepth 1 -type f -name '*.json' -print \
    | while IFS= read -r manifest_path; do
        manifest_component="$(jq -r '.component // empty' "$manifest_path")"
        manifest_channel="$(jq -r '.release_channel // empty' "$manifest_path")"
        manifest_version="$(jq -r '.version // empty' "$manifest_path")"

        if [ "$manifest_component" = "$component" ] && [ "$manifest_channel" = "stable" ]; then
          printf '%s %s\n' "$manifest_version" "$manifest_path"
        fi
      done \
    | sort -V \
    | tail -n 1
)"

if [ -z "$selection" ]; then
  printf 'No stable manifest found for component: %s\n' "$component" >&2
  exit 1
fi

printf '%s\n' "${selection#* }"
