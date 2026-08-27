#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="oh-myusage"
EXECUTABLE_NAME="OhMyUsage"
BUNDLE_ID="com.oh-myusage.app"
DIST_DIR="$ROOT_DIR/dist"
TMP_ROOT="$(mktemp -d /tmp/aibm_pkg.XXXXXX)"
APP_DIR="$TMP_ROOT/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
DMG_STAGING="$TMP_ROOT/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
ZIP_NAME="oh-myusage-macOS.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
RW_DMG_PATH="$TMP_ROOT/$APP_NAME-rw.dmg"
MOUNT_POINT="$TMP_ROOT/mount"
APP_ZIP_PATH="$TMP_ROOT/$APP_NAME.zip"
INSTALL_GUIDE_NAME="安装说明（请先看这里）.txt"
ICON_SOURCE_PATH="$ROOT_DIR/Sources/OhMyUsage/Resources/app_icon_source.png"
ICONSET_DIR="$TMP_ROOT/AppIcon.iconset"
ICNS_PATH="$TMP_ROOT/AppIcon.icns"
INSTALL_GUIDE_PATH="$DMG_STAGING/$INSTALL_GUIDE_NAME"
VERSION_FILE="$ROOT_DIR/VERSION"
APP_VERSION="${APP_VERSION:-}"

if [[ -z "$APP_VERSION" && -f "$VERSION_FILE" ]]; then
  APP_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
fi
if [[ -z "$APP_VERSION" ]]; then
  APP_VERSION="0.0.0"
fi

log() {
  echo "[$APP_NAME] $*"
}

warn() {
  echo "[$APP_NAME] warning: $*" >&2
}

die() {
  echo "[$APP_NAME] error: $*" >&2
  exit 1
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  have_cmd "$1" || die "missing required command: $1"
}

clean_previous_artifacts() {
  mkdir -p "$DIST_DIR"
  log "Cleaning previous package artifacts"

  local artifact
  while IFS= read -r -d '' artifact; do
    log "Removing previous artifact: ${artifact#$ROOT_DIR/}"
    rm -rf "$artifact"
  done < <(
    find "$DIST_DIR" -maxdepth 1 \( \
      -name "$APP_NAME.app" -o \
      -name "$APP_NAME.dmg" -o \
      -name "$APP_NAME [0-9]*.dmg" -o \
      -name "$ZIP_NAME" -o \
      -name "${ZIP_NAME%.zip} [0-9]*.zip" -o \
      -name "AI Plan Monitor.app" -o \
      -name "AI Plan Monitor.dmg" -o \
      -name "AI Plan Monitor [0-9]*.dmg" -o \
      -name "AI-Plan-Monitor-macOS.zip" -o \
      -name "AI-Plan-Monitor-macOS [0-9]*.zip" -o \
      -name "dmg-root" \
    \) -print0
  )
}

has_notary_profile() {
  [[ -n "${NOTARYTOOL_PROFILE:-}" ]]
}

has_notary_apple_id() {
  [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]
}

has_notary_api_key() {
  [[ -n "${APPLE_API_KEY_PATH:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" ]]
}

should_notarize() {
  if [[ "${NOTARIZE_DMG:-}" == "" ]]; then
    has_notary_profile || has_notary_apple_id || has_notary_api_key
    return
  fi

  is_truthy "${NOTARIZE_DMG:-false}"
}

signing_identity() {
  if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    echo "$DEVELOPER_ID_APPLICATION"
  elif [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "$CODESIGN_IDENTITY"
  else
    echo ""
  fi
}

sign_mode() {
  local identity
  identity="$(signing_identity)"
  if [[ -n "$identity" ]]; then
    echo "developer-id"
  else
    echo "ad-hoc"
  fi
}

resolve_binary_path() {
  # Prefer the freshest Release binary. Universal `swift build --arch ...`
  # writes to `.build/apple`, but older Xcode/SwiftPM layouts may leave a
  # stale executable under `.build/out` that would otherwise be picked first.
  local candidates=(
    "$ROOT_DIR/.build/apple/Products/Release/$EXECUTABLE_NAME"
    "$ROOT_DIR/.build/arm64-apple-macosx/release/$EXECUTABLE_NAME"
    "$ROOT_DIR/.build/x86_64-apple-macosx/release/$EXECUTABLE_NAME"
    "$ROOT_DIR/.build/out/Products/Release/$EXECUTABLE_NAME"
  )

  local best=""
  local best_mtime=0
  local candidate mtime
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      mtime="$(stat -f %m "$candidate" 2>/dev/null || echo 0)"
      if (( mtime >= best_mtime )); then
        best="$candidate"
        best_mtime="$mtime"
      fi
    fi
  done

  if [[ -n "$best" ]]; then
    echo "$best"
    return 0
  fi

  return 1
}

build_products_dir() {
  local binary_path="$1"
  dirname "$binary_path"
}

copy_support_files() {
  local products_dir="$1"
  mkdir -p "$RES_DIR" "$FRAMEWORKS_DIR"

  local resource_bundle="$products_dir/${EXECUTABLE_NAME}_${EXECUTABLE_NAME}.bundle"
  if [[ -d "$resource_bundle" ]]; then
    log "Copying SwiftPM resource bundle"
    cp -R "$resource_bundle" "$RES_DIR/"
  fi

  local package_frameworks="$products_dir/PackageFrameworks"
  if [[ -d "$package_frameworks" ]]; then
    log "Copying PackageFrameworks"
    cp -R "$package_frameworks"/. "$FRAMEWORKS_DIR/"
  fi
}

generate_icns() {
  [[ -f "$ICON_SOURCE_PATH" ]] || return 0
  require_cmd sips
  require_cmd iconutil

  rm -rf "$ICONSET_DIR" "$ICNS_PATH"
  mkdir -p "$ICONSET_DIR"

  local sizes=(16 32 128 256 512)
  for size in "${sizes[@]}"; do
    sips -z "$size" "$size" "$ICON_SOURCE_PATH" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    local retina=$((size * 2))
    sips -z "$retina" "$retina" "$ICON_SOURCE_PATH" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
  done

  log "Generating AppIcon.icns"
  iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
  cp "$ICNS_PATH" "$RES_DIR/AppIcon.icns"
}

sign_app_bundle() {
  local target="$1"
  local identity
  identity="$(signing_identity)"

  if ! have_cmd codesign; then
    warn "codesign not found; app bundle will remain unsigned"
    return 0
  fi

  if [[ -n "$identity" ]]; then
    log "Signing app bundle with Developer ID identity"
    codesign --force --deep --options runtime --timestamp --sign "$identity" "$target"
  else
    log "Signing app bundle with ad-hoc identity"
    codesign --force --deep --sign - --timestamp=none "$target"
  fi

  codesign --verify --deep --strict --verbose=2 "$target" >/dev/null
}

sign_disk_image() {
  local target="$1"
  local identity
  identity="$(signing_identity)"

  if ! have_cmd codesign; then
    return 0
  fi

  if [[ -n "$identity" ]]; then
    log "Signing disk image with Developer ID identity"
    codesign --force --timestamp --sign "$identity" "$target"
    codesign --verify --strict --verbose=2 "$target" >/dev/null
  fi
}

assess_bundle() {
  local target="$1"
  if have_cmd spctl; then
    spctl --assess --type exec --verbose=2 "$target" || true
  fi
}

notary_submit() {
  local artifact="$1"
  require_cmd xcrun

  if has_notary_profile; then
    xcrun notarytool submit "$artifact" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
    return 0
  fi

  if has_notary_api_key; then
    xcrun notarytool submit "$artifact" \
      --key "$APPLE_API_KEY_PATH" \
      --key-id "$APPLE_API_KEY_ID" \
      --issuer "$APPLE_API_ISSUER_ID" \
      --wait
    return 0
  fi

  if has_notary_apple_id; then
    xcrun notarytool submit "$artifact" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --wait
    return 0
  fi

  die "NOTARIZE_DMG is enabled but no notarization credentials were provided"
}

staple_artifact() {
  local target="$1"
  require_cmd xcrun
  xcrun stapler staple "$target"
}

prepare_install_guide() {
  cat > "$INSTALL_GUIDE_PATH" <<EOF
${APP_NAME} 安装说明

1. 将 “${APP_NAME}.app” 拖到 “Applications” 文件夹。
2. 第一次打开时，请前往“应用程序”文件夹，右键 ${APP_NAME}，选择“打开”。
3. 如果系统仍然拦截：
   打开“系统设置” -> “隐私与安全性” -> 找到 ${APP_NAME} -> 点击“仍要打开”。

说明：
- 这是 GitHub 开源分发版本，可能会被 macOS Gatekeeper 首次拦截。
- 完成一次“右键打开”后，后续通常可以正常启动。
EOF
}

customize_dmg_window() {
  local volume_name="$1"
  require_cmd osascript

  osascript <<EOF || warn "Skipping Finder DMG window customization"
tell application "Finder"
  tell disk "$volume_name"
    open
    delay 1
    tell container window
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      set bounds to {120, 120, 840, 540}
    end tell
    tell icon view options of container window
      set arrangement to not arranged
      set icon size to 128
      set text size to 14
    end tell
    set position of item "$APP_NAME.app" of container window to {180, 360}
    set position of item "Applications" of container window to {540, 360}
    update without registering applications
    delay 2
    close
    open
    delay 2
    close
  end tell
end tell
EOF
}

# Remove old distributables first so a failed package run cannot leave stale output.
clean_previous_artifacts

# Always build fresh release before packaging to avoid stale DMG content.
# SWIFT_BUILD_SYSTEM 可覆盖构建系统（如 native），适配本机工具链 quirks。
log "Building universal release binary..."
swift build -c release --arch arm64 --arch x86_64 ${SWIFT_BUILD_SYSTEM:+--build-system "$SWIFT_BUILD_SYSTEM"}

BIN_PATH="$(resolve_binary_path || true)"

if [[ ! -x "$BIN_PATH" ]]; then
  die "release binary not found at: $BIN_PATH"
fi

PRODUCTS_DIR="$(build_products_dir "$BIN_PATH")"

mkdir -p "$MACOS_DIR" "$RES_DIR" "$FRAMEWORKS_DIR" "$DMG_STAGING"

cp "$BIN_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"
copy_support_files "$PRODUCTS_DIR"
generate_icns
log "Using binary: $BIN_PATH"
file "$MACOS_DIR/$EXECUTABLE_NAME" || true

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>OhMyUsage</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>NSApplicationIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIcons</key>
  <dict>
    <key>CFBundlePrimaryIcon</key>
    <dict>
      <key>CFBundleIconFile</key>
      <string>AppIcon</string>
      <key>CFBundleIconName</key>
      <string>AppIcon</string>
    </dict>
  </dict>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# Remove filesystem metadata that can invalidate app bundles (e.g. FinderInfo).
if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_DIR" >/dev/null 2>&1 || true
fi

if should_notarize && [[ -z "$(signing_identity)" ]]; then
  die "notarization requires DEVELOPER_ID_APPLICATION (or CODESIGN_IDENTITY) to be set"
fi

log "Packaging mode: $(sign_mode)"
sign_app_bundle "$APP_DIR"
assess_bundle "$APP_DIR"

if should_notarize; then
  log "Creating app zip for notarization"
  require_cmd ditto
  rm -f "$APP_ZIP_PATH"
  ditto -c -k --keepParent "$APP_DIR" "$APP_ZIP_PATH"
  log "Submitting app zip for notarization"
  notary_submit "$APP_ZIP_PATH"
  log "Stapling app bundle"
  staple_artifact "$APP_DIR"
fi

require_cmd ditto
log "Creating distributable ZIP"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

cp -R "$APP_DIR" "$DMG_STAGING/"
prepare_install_guide
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDRW \
  "$RW_DMG_PATH" >/dev/null

mkdir -p "$MOUNT_POINT"
hdiutil attach "$RW_DMG_PATH" -mountpoint "$MOUNT_POINT" -noautoopen >/dev/null
customize_dmg_window "$APP_NAME"
hdiutil detach "$MOUNT_POINT" >/dev/null

hdiutil convert "$RW_DMG_PATH" -ov -format UDZO -o "$DMG_PATH" >/dev/null

sign_disk_image "$DMG_PATH"

if should_notarize; then
  log "Submitting DMG for notarization"
  notary_submit "$DMG_PATH"
  log "Stapling DMG"
  staple_artifact "$DMG_PATH"
fi

log "DMG: $DMG_PATH"
log "ZIP: $ZIP_PATH"
log "TMP_APP: $APP_DIR"
