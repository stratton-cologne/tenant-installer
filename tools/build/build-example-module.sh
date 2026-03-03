#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE_DIR="$PROJECT_ROOT/module-manager/fixtures/example-module"
OUTPUT_DIR="$PROJECT_ROOT/artifacts/modules"
OUTPUT_FILE="$OUTPUT_DIR/example-module-1.0.0.zip"

usage() {
  printf 'Usage: %s [--output-dir <dir>]\n' "$(basename "$0")" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-dir)
      shift
      [ "$#" -gt 0 ] || usage
      OUTPUT_DIR="$1"
      OUTPUT_FILE="$OUTPUT_DIR/example-module-1.0.0.zip"
      ;;
    *)
      usage
      ;;
  esac
  shift
done

if [ ! -d "$FIXTURE_DIR" ]; then
  printf 'Fixture directory not found: %s\n' "$FIXTURE_DIR" >&2
  exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
  printf 'zip is required to build the example module artifact.\n' >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_FILE"

(
  cd "$FIXTURE_DIR"
  zip -rq "$OUTPUT_FILE" module.json backend frontend
)

printf '%s\n' "$OUTPUT_FILE"
