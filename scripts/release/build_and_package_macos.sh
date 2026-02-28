#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-Momentum.xcodeproj}"
SCHEME="${SCHEME:-Momentum}"
DESTINATION="${DESTINATION:-generic/platform=macOS}"
DERIVED_DATA="${DERIVED_DATA:-$PWD/.derivedData-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$PWD/release-artifacts}"
APP_NAME="${APP_NAME:-Momentum}"
RELEASE_TAG="${RELEASE_TAG:-}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"

if [[ -z "$RELEASE_TAG" ]]; then
  echo "RELEASE_TAG is required (example: v1.8.0)" >&2
  exit 1
fi

release_version="${RELEASE_TAG#v}"
mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR"/*

xcode_common_args=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -derivedDataPath "$DERIVED_DATA"
  -configuration Release
  "CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
  "CODE_SIGNING_ALLOWED=NO"
  "CODE_SIGNING_REQUIRED=NO"
  "CODE_SIGN_IDENTITY="
  "ONLY_ACTIVE_ARCH=NO"
)

extract_build_setting() {
  local settings="$1"
  local key="$2"
  awk -F ' = ' -v wanted="$key" '$1 ~ ("^[[:space:]]*" wanted "[[:space:]]*$") { print $2; exit }' <<<"$settings"
}

verify_binary_arches() {
  local executable_path="$1"
  shift
  local expected_arches=("$@")

  if [[ ! -f "$executable_path" ]]; then
    echo "Executable not found at $executable_path" >&2
    return 1
  fi

  local lipo_info
  lipo_info="$(lipo -info "$executable_path")"
  echo "Binary architecture info: $lipo_info"

  for arch in "${expected_arches[@]}"; do
    if ! grep -q "$arch" <<<"$lipo_info"; then
      echo "Expected architecture '$arch' not present in $executable_path" >&2
      return 1
    fi
  done
}

verify_zip_contains_app() {
  local zip_path="$1"
  local zip_listing
  if [[ ! -f "$zip_path" || ! -s "$zip_path" ]]; then
    echo "ZIP file missing or empty: $zip_path" >&2
    return 1
  fi

  zip_listing="$(unzip -l "$zip_path")"
  if ! grep -Eq "[[:space:]]${APP_NAME}\\.app(/|$)" <<<"$zip_listing"; then
    echo "ZIP does not contain ${APP_NAME}.app: $zip_path" >&2
    return 1
  fi
}

verify_dmg() {
  local dmg_path="$1"
  if [[ ! -f "$dmg_path" || ! -s "$dmg_path" ]]; then
    echo "DMG file missing or empty: $dmg_path" >&2
    return 1
  fi
  hdiutil verify "$dmg_path" >/dev/null
}

package_bundle() {
  local app_path="$1"
  local label="$2"

  local zip_name="${APP_NAME}-macOS-${label}.zip"
  local dmg_name="${APP_NAME}-macOS-${label}.dmg"
  local zip_path="$OUTPUT_DIR/$zip_name"
  local dmg_path="$OUTPUT_DIR/$dmg_name"
  local stage_dir
  stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/momentum-release-${label}.XXXXXX")"

  COPYFILE_DISABLE=1 ditto --norsrc -c -k --keepParent "$app_path" "$zip_path"

  COPYFILE_DISABLE=1 ditto --norsrc "$app_path" "$stage_dir/${APP_NAME}.app"
  ln -s /Applications "$stage_dir/Applications"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$stage_dir" \
    -ov \
    -format UDZO \
    "$dmg_path" >/dev/null
  rm -rf "$stage_dir"

  verify_zip_contains_app "$zip_path" || return 1
  verify_dmg "$dmg_path" || return 1
}

build_and_package() {
  local label="$1"
  local archs="$2"
  shift 2
  local expected_arches=("$@")

  echo "Building Release ($label) with ARCHS='$archs'"
  xcodebuild "${xcode_common_args[@]}" "ARCHS=$archs" clean build

  local settings
  settings="$(xcodebuild "${xcode_common_args[@]}" "ARCHS=$archs" -showBuildSettings)"

  local build_dir
  local full_product_name
  local executable_name
  build_dir="$(extract_build_setting "$settings" "BUILT_PRODUCTS_DIR")"
  full_product_name="$(extract_build_setting "$settings" "FULL_PRODUCT_NAME")"
  executable_name="$(extract_build_setting "$settings" "EXECUTABLE_NAME")"

  if [[ -z "$build_dir" || -z "$full_product_name" || -z "$executable_name" ]]; then
    echo "Failed to read required build settings." >&2
    return 1
  fi

  local app_path="$build_dir/$full_product_name"
  local executable_path="$app_path/Contents/MacOS/$executable_name"

  if [[ ! -d "$app_path" ]]; then
    echo "App bundle not found at $app_path" >&2
    return 1
  fi

  verify_binary_arches "$executable_path" "${expected_arches[@]}" || return 1
  package_bundle "$app_path" "$label" || return 1
}

build_variant=""
set +e
build_and_package "universal" "arm64 x86_64" "arm64" "x86_64"
universal_status=$?
set -e

if [[ $universal_status -eq 0 ]]; then
  build_variant="universal"
else
  echo "Universal build failed. Falling back to split architecture assets." >&2
  rm -f "$OUTPUT_DIR/${APP_NAME}-macOS-universal.dmg" "$OUTPUT_DIR/${APP_NAME}-macOS-universal.zip"
  build_and_package "arm64" "arm64" "arm64"
  build_and_package "x86_64" "x86_64" "x86_64"
  build_variant="split"
fi

(
  cd "$OUTPUT_DIR"
  shasum -a 256 ./*.dmg ./*.zip >checksums.txt
)

cat >"$OUTPUT_DIR/release-metadata.txt" <<EOF
tag=$RELEASE_TAG
version=$release_version
build_number=$BUILD_NUMBER
build_variant=$build_variant
generated_at_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

echo "Release artifacts created:"
ls -1 "$OUTPUT_DIR"
