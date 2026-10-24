#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
"$ROOT/build.sh"
APP_SRC="$ROOT/build/Hidex.app"
APP_DST="/Applications/Hidex.app"
IDENTIFIER="com.jimmks7.hidex"

SIGN_ID="$("$ROOT/scripts/ensure-signing-identity.sh")"

killall Hidex T650Gestures 2>/dev/null || true
sleep 0.5

rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"

codesign --force --sign "$SIGN_ID" --identifier "$IDENTIFIER" "$APP_DST"

if codesign -dv "$APP_DST" 2>&1 | grep -q 'Signature=adhoc'; then
  echo "ERROR: installed app is ad-hoc; aborting open." >&2
  exit 1
fi

echo "Installed to $APP_DST"
codesign -dv "$APP_DST" 2>&1 | egrep 'Authority|Identifier|Signature' || true
open "$APP_DST"
echo ""
echo "Si Spaces ←→ fallan tras el primer install con firma Local:"
echo "  Ajustes → Privacidad → Accesibilidad → quita entradas viejas de Hidex / T650Gestures"
echo "  → + → /Applications/Hidex.app → activar → Reiniciar app (menú)"
echo "Log: ~/.hidex.log"
