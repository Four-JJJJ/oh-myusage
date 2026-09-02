#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="oh-myusage"
EXECUTABLE_NAME="OhMyUsage"
# 固定 Bundle ID（优化文档 11.2）：不得随版本、APP_VERSION 或构建机器变化，
# 以保持 Keychain 访问组与用户设置的连续性。请勿改成从 VERSION 或环境变量推导。
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
# 扩展属性清理只允许针对这个资源目录（优化文档 11.4）。
RESOURCES_DIR="$ROOT_DIR/Sources/OhMyUsage/Resources"

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
      -name "SHA256SUMS.txt" -o \
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

# 签名优先级（优化文档 11.3）：
#   1. DEVELOPER_ID_APPLICATION —— 拥有 Apple Developer ID 时使用（唯一可公证的路径）
#   2. LOCAL_CODESIGN_IDENTITY  —— 可选的本地自签名证书（不等于 Developer ID，不能消除 Gatekeeper 首次提示）
#   3. ad-hoc "-"               —— 默认回退
# CODESIGN_IDENTITY 作为历史兼容别名保留，排在 LOCAL_CODESIGN_IDENTITY 之后。
# 证书私钥只保存在登录钥匙串，脚本不读取、不写入仓库、也不回显任何身份或私钥内容。
signing_identity() {
  if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    echo "$DEVELOPER_ID_APPLICATION"
  elif [[ -n "${LOCAL_CODESIGN_IDENTITY:-}" ]]; then
    echo "$LOCAL_CODESIGN_IDENTITY"
  elif [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "$CODESIGN_IDENTITY"
  else
    echo ""
  fi
}

# 只有实际签名身份来自 DEVELOPER_ID_APPLICATION 时才允许 notarization；
# 自签名 / ad-hoc 构建一律不得公证，也不得输出任何"已公证"字样。
developer_id_signing() {
  [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]
}

# 运行 codesign；失败时只输出退出码，避免身份/证书细节进入构建日志。
run_codesign() {
  local step="$1"
  shift
  local status=0
  "$@" >/dev/null 2>&1 || status=$?
  if (( status != 0 )); then
    die "$step failed (codesign exit code: $status)"
  fi
}

sign_mode() {
  if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    echo "developer-id"
  elif [[ -n "$(signing_identity)" ]]; then
    echo "local-codesign (self-signed, not Developer ID)"
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

  if [[ -n "$identity" ]] && developer_id_signing; then
    log "Signing app bundle with Developer ID identity"
    run_codesign "Signing app bundle" \
      codesign --force --deep --options runtime --timestamp --sign "$identity" "$target"
  elif [[ -n "$identity" ]]; then
    # 本地自签名：不等于 Developer ID，不能消除 Gatekeeper 首次提示。
    # 不加 --timestamp（避免依赖 Apple 时间戳服务），行为尽量贴近 ad-hoc。
    log "Signing app bundle with local self-signed identity (not a Developer ID; Gatekeeper will still warn on first launch)"
    run_codesign "Signing app bundle" \
      codesign --force --deep --sign "$identity" "$target"
  else
    log "Signing app bundle with ad-hoc identity"
    run_codesign "Signing app bundle" \
      codesign --force --deep --sign - --timestamp=none "$target"
  fi

  run_codesign "Verifying app bundle signature" \
    codesign --verify --deep --strict --verbose=2 "$target"
}

sign_disk_image() {
  local target="$1"
  local identity
  identity="$(signing_identity)"

  if ! have_cmd codesign; then
    return 0
  fi

  if [[ -n "$identity" ]] && developer_id_signing; then
    log "Signing disk image with Developer ID identity"
    run_codesign "Signing disk image" \
      codesign --force --timestamp --sign "$identity" "$target"
    run_codesign "Verifying disk image signature" \
      codesign --verify --strict --verbose=2 "$target"
  elif [[ -n "$identity" ]]; then
    log "Signing disk image with local self-signed identity (not a Developer ID)"
    run_codesign "Signing disk image" \
      codesign --force --sign "$identity" "$target"
    run_codesign "Verifying disk image signature" \
      codesign --verify --strict --verbose=2 "$target"
  fi
}

assess_bundle() {
  local target="$1"
  # ad-hoc / 自签名构建未公证，spctl assess 失败是预期行为，不算打包失败。
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
# 构建前只清理资源目录的扩展属性，避免 bundle 资源被 FinderInfo/quarantine 污染
# （优化文档 11.4）。禁止对 $HOME、仓库根或其他宽泛路径递归执行 xattr。
if command -v xattr >/dev/null 2>&1 && [[ -d "$RESOURCES_DIR" ]]; then
  xattr -cr "$RESOURCES_DIR" >/dev/null 2>&1 || true
fi

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
# 范围仅限 $APP_DIR（优化文档 11.4）：禁止对 $HOME、仓库根或其他宽泛路径递归执行。
if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_DIR" >/dev/null 2>&1 || true
fi

# Notarization 门控（优化文档 11.3）：没有 Developer ID 签名身份时绝不执行公证。
# 自签名 / ad-hoc 构建一律跳过，且后续输出不得出现"已公证"之类的误导描述。
NOTARIZE_ENABLED=0
if should_notarize; then
  if developer_id_signing; then
    NOTARIZE_ENABLED=1
  elif is_truthy "${NOTARIZE_DMG:-false}"; then
    die "NOTARIZE_DMG is enabled but notarization requires a Developer ID signing identity (DEVELOPER_ID_APPLICATION); ad-hoc or self-signed builds cannot be notarized"
  else
    warn "Notarization credentials detected but signing will not use a Developer ID identity; skipping notarization (this build is NOT notarized)"
  fi
fi

log "Packaging mode: $(sign_mode)"
sign_app_bundle "$APP_DIR"
assess_bundle "$APP_DIR"

if (( NOTARIZE_ENABLED )); then
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

if (( NOTARIZE_ENABLED )); then
  log "Submitting DMG for notarization"
  notary_submit "$DMG_PATH"
  log "Stapling DMG"
  staple_artifact "$DMG_PATH"
fi

# 生成 SHA-256 校验文件（优化文档 11.5）：shasum -a 256 输出风格，"摘要 + 两个空格 + 文件名"。
# 文件名使用相对路径，便于用户在任意目录校验下载产物。
require_cmd shasum
(
  cd "$DIST_DIR"
  shasum -a 256 "$APP_NAME.dmg" "$ZIP_NAME" > "SHA256SUMS.txt"
)

log "DMG: $DMG_PATH"
log "ZIP: $ZIP_PATH"
log "SHA256SUMS: $DIST_DIR/SHA256SUMS.txt"
log "TMP_APP: $APP_DIR"

# 如实输出公证状态：未公证时必须明确说明，不得出现"已公证"字样。
if (( NOTARIZE_ENABLED )); then
  log "Notarization: submitted and stapled"
else
  log "Notarization: not performed — this build is NOT notarized; users will see a Gatekeeper warning on first launch (see docs/INSTALL_UNSIGNED.md)"
fi
cat "$DIST_DIR/SHA256SUMS.txt"
