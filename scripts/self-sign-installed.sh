#!/bin/bash
# Re-sign /Applications/Hidex.app with a *local* identity created on this Mac.
# This cannot replace Apple notarization for Gatekeeper on first open, but it
# keeps Accessibility TCC stable across rebuilds for developers and power users.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-/Applications/Hidex.app}"
IDENTIFIER="com.jimmks7.hidex"

if [[ ! -d "$APP" ]]; then
  echo "App not found: $APP" >&2
  echo "Install from the DMG/PKG first, or pass a path: $0 /path/to/Hidex.app" >&2
  exit 1
fi

SIGN_ID="$("$ROOT/scripts/ensure-signing-identity.sh")"
echo "Re-signing $APP with Hidex Local ($SIGN_ID)…"
codesign --force --deep --sign "$SIGN_ID" --identifier "$IDENTIFIER" "$APP"
codesign -dv "$APP" 2>&1 | egrep 'Authority|Identifier|Signature' || true
echo ""
echo "Next:"
echo "  1) System Settings → Privacy & Security → Accessibility → remove old Hidex entries"
echo "  2) Add $APP and enable it"
echo "  3) Automation → Hidex → System Events"
echo "  4) Menu → Relaunch app"
