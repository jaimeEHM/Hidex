#!/bin/bash
set -euo pipefail

APP_NAME="Hidex"
IDENTIFIER="com.jimmks7.hidex"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

echo "Building $APP_NAME $VERSION..."

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"

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

swiftc -O \
  -target arm64-apple-macos13.0 \
  -framework Cocoa \
  -framework IOKit \
  -framework SwiftUI \
  -framework ApplicationServices \
  -o "$MACOS_DIR/$APP_NAME" \
  "${SOURCES[@]}"

cp "$ROOT/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"

SIGN_ID="$("$ROOT/scripts/ensure-signing-identity.sh")"
echo "Signing with identity hash: $SIGN_ID"
codesign --force --sign "$SIGN_ID" --identifier "$IDENTIFIER" "$APP_BUNDLE"

CS_OUT="$(codesign -dv "$APP_BUNDLE" 2>&1)"
if echo "$CS_OUT" | grep -q 'Signature=adhoc'; then
  echo "ERROR: app is still ad-hoc signed; Accessibility will not stick." >&2
  echo "$CS_OUT" | head -20 >&2
  exit 1
fi
if ! echo "$CS_OUT" | grep -Eq 'Authority=Hidex Local|Signature size=[1-9]'; then
  echo "ERROR: expected stable (non-adhoc) signature" >&2
  echo "$CS_OUT" | head -20 >&2
  exit 1
fi
echo "$CS_OUT" | egrep 'Authority|Signature|Identifier' || true

echo ""
echo "Built: $APP_BUNDLE"
echo "Log: ~/.hidex.log"
