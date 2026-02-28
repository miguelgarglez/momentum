#!/usr/bin/env bash
set -euo pipefail

RELEASE_TAG="${RELEASE_TAG:-}"
OUTPUT_DIR="${OUTPUT_DIR:-$PWD/release-artifacts}"

if [[ -z "$RELEASE_TAG" ]]; then
  echo "RELEASE_TAG is required (example: v1.8.0)" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required to upload release assets." >&2
  exit 1
fi

dmg_files=()
while IFS= read -r file; do
  dmg_files+=("$file")
done < <(find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.dmg' | sort)

zip_files=()
while IFS= read -r file; do
  zip_files+=("$file")
done < <(find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.zip' | sort)

checksums_file="$OUTPUT_DIR/checksums.txt"
metadata_file="$OUTPUT_DIR/release-metadata.txt"

if [[ ${#dmg_files[@]} -eq 0 ]]; then
  echo "No DMG files found in $OUTPUT_DIR" >&2
  exit 1
fi

if [[ ${#zip_files[@]} -eq 0 ]]; then
  echo "No ZIP files found in $OUTPUT_DIR" >&2
  exit 1
fi

if [[ ! -f "$checksums_file" ]]; then
  echo "checksums.txt not found in $OUTPUT_DIR" >&2
  exit 1
fi

assets=(
  "${dmg_files[@]}"
  "${zip_files[@]}"
  "$checksums_file"
)

if [[ -f "$metadata_file" ]]; then
  assets+=("$metadata_file")
fi

echo "Uploading ${#assets[@]} release assets to $RELEASE_TAG"
gh release upload "$RELEASE_TAG" "${assets[@]}" --clobber
