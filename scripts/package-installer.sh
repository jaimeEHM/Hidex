#!/bin/bash
# Create a distributable DMG + PKG (universal app).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Hidex"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
DIST="$ROOT/dist"
STAGE="$DIST/stage"
APP_SRC="$ROOT/build/$APP_NAME.app"
DMG="$DIST/${APP_NAME}-${VERSION}-universal.dmg"
PKG="$DIST/${APP_NAME}-${VERSION}-universal.pkg"
IDENTIFIER="com.jimmks7.hidex"

"$ROOT/scripts/build-universal.sh"

if [[ ! -d "$APP_SRC" ]]; then
  echo "Missing $APP_SRC" >&2
  exit 1
fi

rm -rf "$DIST"
mkdir -p "$STAGE" "$DIST/pkgroot/Applications"

cp -R "$APP_SRC" "$STAGE/$APP_NAME.app"
cp -R "$APP_SRC" "$DIST/pkgroot/Applications/$APP_NAME.app"
ln -sf /Applications "$STAGE/Applications"

echo "Creating DMG…"
hdiutil create -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG"

echo "Creating PKG…"
pkgbuild \
  --root "$DIST/pkgroot" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location "/" \
  "$PKG"

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
echo "Optional stable local resign: ./scripts/self-sign-installed.sh"
