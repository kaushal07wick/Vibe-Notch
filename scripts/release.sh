#!/usr/bin/env bash
# Release build → signed .app → dist/VibeNotch-<version>.dmg
# Uses a Developer ID identity when available, else ad-hoc signs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist")"
APP="$ROOT/.build/VibeNotch.app"
DIST="$ROOT/dist"
DMG="$DIST/VibeNotch-$VERSION.dmg"

cd "$ROOT"
python3 scripts/make-icon.py
./scripts/bundle.sh release
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
plutil -replace CFBundleIconFile -string AppIcon "$APP/Contents/Info.plist"

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Developer ID Application' | sed -E 's/.*"(.+)"/\1/' || true)"
if [ -n "$IDENTITY" ]; then
  echo "Signing with: $IDENTITY"
  codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"
else
  echo "No Developer ID found — ad-hoc signing (Gatekeeper will warn on other Macs)"
  codesign --force --deep --sign - "$APP"
fi

mkdir -p "$DIST"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/VibeNotch.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Vibe Notch" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Built $DMG"
