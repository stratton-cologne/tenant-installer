#!/usr/bin/env bash

set -eu

if [ "$#" -ne 3 ]; then
  printf 'Usage: %s <manifest.json> <github-repo> <tag-prefix>\n' "$(basename "$0")" >&2
  exit 1
fi

manifest_path="$1"
github_repo="$2"
tag_prefix="$3"

if [ ! -f "$manifest_path" ]; then
  printf 'Manifest not found: %s\n' "$manifest_path" >&2
  exit 1
fi

if [ -z "$github_repo" ]; then
  printf 'GitHub repo is required, e.g. owner/repo.\n' >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'jq is required to build GitHub release URLs.\n' >&2
  exit 1
fi

version="$(jq -r '.version // empty' "$manifest_path")"
file_name="$(jq -r '.artifact.file_name // empty' "$manifest_path")"

[ -n "$version" ] || { printf 'Manifest missing version.\n' >&2; exit 1; }
[ -n "$file_name" ] || { printf 'Manifest missing artifact.file_name.\n' >&2; exit 1; }

tag="${tag_prefix}${version}"
printf 'https://github.com/%s/releases/download/%s/%s\n' "$github_repo" "$tag" "$file_name"
