#!/bin/bash
# Build Assets/AppIcon.icns from Assets/HidexIcon-1024.png
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTER="$ROOT/Assets/HidexIcon-1024.png"
SRC_JPG="/Users/jimmks7/.cursor/projects/Users-jimmks7-Proyectos-touchpadLogitech/assets/HidexIcon.jpg"
ICONSET="$ROOT/Assets/AppIcon.iconset"
ICNS="$ROOT/Assets/AppIcon.icns"

mkdir -p "$ROOT/Assets"
if [[ ! -f "$MASTER" ]]; then
  if [[ -f "$SRC_JPG" ]]; then
    sips -s format png -z 1024 1024 "$SRC_JPG" --out "$MASTER" >/dev/null
  else
    echo "Missing master icon PNG/JPG" >&2
    exit 1
  fi
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"

# Explicit sizes, then copy into iconutil-required filenames.
sips -s format png -z 16 16 "$MASTER" --out "$TMP/a.png" >/dev/null
sips -s format png -z 32 32 "$MASTER" --out "$TMP/b.png" >/dev/null
sips -s format png -z 64 64 "$MASTER" --out "$TMP/c.png" >/dev/null
sips -s format png -z 128 128 "$MASTER" --out "$TMP/d.png" >/dev/null
sips -s format png -z 256 256 "$MASTER" --out "$TMP/e.png" >/dev/null
sips -s format png -z 512 512 "$MASTER" --out "$TMP/f.png" >/dev/null
sips -s format png -z 1024 1024 "$MASTER" --out "$TMP/g.png" >/dev/null

cp "$TMP/a.png" "$SET/icon_16x16.png"
cp "$TMP/b.png" "$SET/icon_32x32.png"
cp "$TMP/d.png" "$SET/icon_128x128.png"
cp "$TMP/e.png" "$SET/icon_256x256.png"
cp "$TMP/f.png" "$SET/icon_512x512.png"

# Retina filenames use an at-sign before 2x.png
AT2X="$(printf '%s' '@')2x.png"
cp "$TMP/b.png" "$SET/icon_16x16${AT2X}"
cp "$TMP/c.png" "$SET/icon_32x32${AT2X}"
cp "$TMP/e.png" "$SET/icon_128x128${AT2X}"
cp "$TMP/f.png" "$SET/icon_256x256${AT2X}"
cp "$TMP/g.png" "$SET/icon_512x512${AT2X}"

echo "Iconset contents:"
ls -la "$SET"

iconutil -c icns "$SET" -o "$ICNS"
rm -rf "$ICONSET"
cp -R "$SET" "$ICONSET"
ls -lah "$ICNS"
file "$ICNS"
echo "OK: $ICNS"
