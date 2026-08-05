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

ENTITLEMENTS="$ROOT/Resources/VibeNotch.entitlements"

# Sign inside-out: helpers first, bundle last. `--deep` is not supported by
# Apple for signing (only for verifying) and leaves nested binaries with the
# wrong entitlements — which is how a notarized build ends up with working
# menus and dead terminal jump / reply / model-switch.
sign() {
  codesign --force --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" --sign "$1" "$2"
}

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Developer ID Application' | sed -E 's/.*"(.+)"/\1/' || true)"
if [ -n "$IDENTITY" ]; then
  echo "Signing with: $IDENTITY"
  for helper in "$APP/Contents/Helpers/"*; do sign "$IDENTITY" "$helper"; done
  sign "$IDENTITY" "$APP"
else
  echo "No Developer ID found — ad-hoc signing."
  echo "  Gatekeeper BLOCKS ad-hoc-signed apps downloaded from the internet."
  echo "  Fine for local builds; a published DMG needs Developer ID + notarization."
  # Ad-hoc can't carry a secure timestamp, and entitlements are meaningless
  # without a real identity — sign plainly so the local build still runs.
  for helper in "$APP/Contents/Helpers/"*; do codesign --force --sign - "$helper"; done
  codesign --force --sign - "$APP"
fi

mkdir -p "$DIST"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/VibeNotch.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Vibe Notch" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Built $DMG"

# Notarization is what stops macOS showing "VibeNotch is damaged and can't be
# opened" to everyone who downloads the DMG. One-time setup:
#   xcrun notarytool store-credentials vibenotch \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
# then run with NOTARY_PROFILE=vibenotch.
if [ -n "$IDENTITY" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "Notarizing…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  echo "Notarized and stapled — this DMG opens cleanly on any Mac."
else
  echo "NOT notarized. This DMG will be blocked by Gatekeeper if downloaded."
  echo "  Set NOTARY_PROFILE (and have a Developer ID) to notarize."
fi
