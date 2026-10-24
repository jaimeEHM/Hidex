#!/bin/bash
# Create a distributable DMG + PKG (universal app).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="T650Gestures"
VERSION="1.1.0"
DIST="$ROOT/dist"
STAGE="$DIST/stage"
APP_SRC="$ROOT/build/$APP_NAME.app"
DMG="$DIST/${APP_NAME}-${VERSION}-universal.dmg"
PKG="$DIST/${APP_NAME}-${VERSION}-universal.pkg"
IDENTIFIER="com.t650.gestures"

"$ROOT/scripts/build-universal.sh"

if [[ ! -d "$APP_SRC" ]]; then
  echo "Missing $APP_SRC" >&2
  exit 1
fi

rm -rf "$DIST"
mkdir -p "$STAGE" "$DIST/pkgroot/Applications"

cp -R "$APP_SRC" "$STAGE/$APP_NAME.app"
cp -R "$APP_SRC" "$DIST/pkgroot/Applications/$APP_NAME.app"

# Optional: Applications symlink for drag-install UX
ln -sf /Applications "$STAGE/Applications"

# --- DMG ---
echo "Creating DMG…"
hdiutil create -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG"

# --- PKG ---
echo "Creating PKG…"
pkgbuild \
  --root "$DIST/pkgroot" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location "/" \
  "$PKG"

# Checksums
(
  cd "$DIST"
  shasum -a 256 "$(basename "$DMG")" "$(basename "$PKG")" > SHA256SUMS.txt
)

echo ""
echo "Artifacts:"
ls -lh "$DMG" "$PKG" "$DIST/SHA256SUMS.txt"
file "$APP_SRC/Contents/MacOS/$APP_NAME"
cat "$DIST/SHA256SUMS.txt"
echo ""
echo "Note: Not notarized (no Apple Developer ID). Users may need:"
echo "  System Settings → Privacy → Open Anyway, then Accessibility + Automation."
