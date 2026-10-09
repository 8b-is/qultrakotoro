#!/usr/bin/env bash
# Build a real macOS .app bundle for KotoroMac, end to end, no Xcode project.
#
#   scripts/build-mac-app.sh [debug|release]   (default: release)
#
# Output: build/qUltraKotoro.app  → launch with `open build/qUltraKotoro.app`
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
VERSION="0.2.0"
PRODUCT="KotoroMac"
APP_NAME="qUltraKotoro"
BUNDLE_ID="dev.vaked.qultrakotoro"
MIN_MACOS="14.0"

APP="$ROOT/build/$APP_NAME.app"
ICONSET="$ROOT/build/AppIcon.iconset"
SRC_ICON="$ROOT/Sources/KotoroUI/Resources/Assets.xcassets/AppIcon.appiconset"

echo "==> building $PRODUCT ($CONFIG)"
swift build -c "$CONFIG" --product "$PRODUCT"

BIN=".build/$CONFIG/$PRODUCT"
[ -x "$BIN" ] || { echo "missing binary: $BIN" >&2; exit 1; }

echo "==> assembling $APP"
rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"
cp "$BIN" "$APP/Contents/MacOS/$PRODUCT"

# --- icon: build a proper .icns from the appiconset PNGs -------------------
emit() { sips -z "$2" "$2" "$SRC_ICON/icon-$1.png" --out "$ICONSET/$3" >/dev/null; }
emit 16  16   icon_16x16.png
emit 32  32   icon_16x16@2x.png
emit 32  32   icon_32x32.png
emit 64  64   icon_32x32@2x.png
emit 128 128  icon_128x128.png
emit 256 256  icon_128x128@2x.png
emit 256 256  icon_256x256.png
emit 512 512  icon_256x256@2x.png
emit 512 512  icon_512x512.png
emit 1024 1024 icon_512x512@2x.png
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# --- Info.plist ------------------------------------------------------------
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$PRODUCT</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

# --- ad-hoc sign so Gatekeeper/launchd are happy ---------------------------
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "built $APP"
