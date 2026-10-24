#!/bin/bash
# Build universal (arm64 + x86_64) Hidex.app
set -euo pipefail

APP_NAME="Hidex"
IDENTIFIER="com.jimmks7.hidex"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
MIN_OS="13.0"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/Info.plist" 2>/dev/null || echo 4)"

SOURCES=(
  "$ROOT/Sources/HIDPP/HIDPPTypes.swift"
  "$ROOT/Sources/HIDPP/HIDLocator.swift"
  "$ROOT/Sources/HIDPP/HIDPPSession.swift"
  "$ROOT/Sources/Multitouch/RawXYParser.swift"
  "$ROOT/Sources/Multitouch/TouchTracker.swift"
  "$ROOT/Sources/Gestures/GestureConfig.swift"
  "$ROOT/Sources/Gestures/SpaceSwitcher.swift"
  "$ROOT/Sources/Gestures/InputInjector.swift"
  "$ROOT/Sources/Gestures/GestureEngine.swift"
  "$ROOT/Sources/App/L10n.swift"
  "$ROOT/Sources/App/StatusItemIcon.swift"
  "$ROOT/Sources/App/PreferencesView.swift"
  "$ROOT/Sources/App/GestureLabView.swift"
  "$ROOT/Sources/App/AppDelegate.swift"
  "$ROOT/Sources/App/main.swift"
)

FRAMEWORKS=(
  -framework Cocoa
  -framework IOKit
  -framework SwiftUI
  -framework ApplicationServices
)

echo "Building universal $APP_NAME $VERSION (arm64 + x86_64)…"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$BUILD_DIR/obj"

compile_arch() {
  local arch="$1"
  local out="$BUILD_DIR/obj/$APP_NAME-$arch"
  echo "  → $arch"
  swiftc -O \
    -target "${arch}-apple-macos${MIN_OS}" \
    "${FRAMEWORKS[@]}" \
    -o "$out" \
    "${SOURCES[@]}"
}

compile_arch arm64
compile_arch x86_64

lipo -create \
  -output "$MACOS_DIR/$APP_NAME" \
  "$BUILD_DIR/obj/$APP_NAME-arm64" \
  "$BUILD_DIR/obj/$APP_NAME-x86_64"

cp "$ROOT/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
mkdir -p "$APP_BUNDLE/Contents/Resources"
if [[ -f "$ROOT/Assets/AppIcon.icns" ]]; then
  cp "$ROOT/Assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

if SIGN_ID="$("$ROOT/scripts/ensure-signing-identity.sh" 2>/dev/null)"; then
  echo "Signing with: $SIGN_ID"
  codesign --force --sign "$SIGN_ID" --identifier "$IDENTIFIER" "$APP_BUNDLE"
else
  echo "WARNING: signing ad-hoc (Accessibility may reset per rebuild)"
  codesign --force --sign - --identifier "$IDENTIFIER" "$APP_BUNDLE"
fi

file "$MACOS_DIR/$APP_NAME"
codesign -dv --verbose=2 "$APP_BUNDLE" 2>&1 | egrep 'Authority|Identifier|Signature|Format' || true
echo ""
echo "Built: $APP_BUNDLE"
