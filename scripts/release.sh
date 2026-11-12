#!/usr/bin/env bash
# Default: signed and notarized. Unsigned public betas require an explicit flag.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PREVIEW=false
UNSIGNED_BETA=false
BASE_VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
VERSION="${RELEASE_VERSION:-$BASE_VERSION-beta.1}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --preview) PREVIEW=true; shift ;;
    --unsigned-beta) UNSIGNED_BETA=true; shift ;;
    --version) VERSION="${2:?--version requires a version}"; shift 2 ;;
    *) echo "Usage: $0 [--preview | --unsigned-beta] [--version x.y.z-beta.n]" >&2; exit 2 ;;
  esac
done
if $PREVIEW && $UNSIGNED_BETA; then echo "Choose preview or unsigned beta, not both." >&2; exit 2; fi
if $UNSIGNED_BETA && [[ ! "$VERSION" =~ -beta\.[0-9]+$ ]]; then echo "Unsigned public builds must use a beta version." >&2; exit 2; fi
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$ ]] || { echo "Invalid release version: $VERSION" >&2; exit 1; }
[ "${VERSION%%-*}" = "$BASE_VERSION" ] || { echo "Release version must match Info.plist $BASE_VERSION." >&2; exit 1; }
IDENTITY="${SIGNING_IDENTITY:-}"
if ! $PREVIEW; then
  [ -z "$(git status --porcelain)" ] || { echo "Public releases require a reviewed, committed, clean source tree. Use --preview for local validation." >&2; exit 1; }
  [ "$(git describe --tags --exact-match HEAD 2>/dev/null || true)" = "v$VERSION" ] || { echo "Public releases require HEAD tagged v$VERSION." >&2; exit 1; }
  if ! $UNSIGNED_BETA; then
  if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)"
  fi
  [ -n "$IDENTITY" ] && [ -n "${NOTARY_PROFILE:-}" ] || { echo "Developer ID Application signing and NOTARY_PROFILE are required. No public artifact was produced." >&2; exit 1; }
  fi
  ./scripts/check.sh
fi
./scripts/bundle.sh release
APP="$ROOT/.build/VibeNotch.app"
python3 scripts/verify-bundle.py "$APP"
python3 scripts/smoke-hook.py "$APP/Contents/Helpers/vibenotch-hook"
DIST="$ROOT/dist"
mkdir -p "$DIST"
STAGE="$(mktemp -d "$ROOT/.build/release-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
notarize() {
  local artifact="$1" report="$2"
  xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$report"
  python3 - "$report" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
if r.get('status')!='Accepted': raise SystemExit('Notarization was not accepted. Review '+sys.argv[1]+' before distributing.')
PY
}
if $PREVIEW; then
  NAME="VibeNotch-$VERSION-LOCAL-PREVIEW"
  echo "LOCAL PREVIEW ONLY: ad-hoc signed, not notarized, not suitable for a public download."
elif $UNSIGNED_BETA; then
  NAME="VibeNotch-$VERSION-UNSIGNED-BETA"
  [ ! -e "$DIST/$NAME.dmg" ] || { echo "Release artifact already exists; refusing to replace it." >&2; exit 1; }
  echo "UNSIGNED BETA: ad-hoc signed, not notarized. macOS may block first launch."
else
  NAME="VibeNotch-$VERSION"
  [ ! -e "$DIST/$NAME.dmg" ] || { echo "Release artifact already exists; refusing to replace it." >&2; exit 1; }
  for binary in "$APP/Contents/Helpers/"* "$APP/Contents/MacOS/VibeNotch"; do
    codesign --force --timestamp --options runtime --entitlements Resources/VibeNotch.entitlements --sign "$IDENTITY" "$binary"
  done
  codesign --force --timestamp --options runtime --entitlements Resources/VibeNotch.entitlements --sign "$IDENTITY" "$APP"
  codesign --verify --deep --strict "$APP"
  ditto -c -k --keepParent "$APP" "$STAGE/notarize.zip"
  notarize "$STAGE/notarize.zip" "$DIST/$NAME-app-notary.json"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
fi
mkdir -p "$STAGE/disk"
ditto "$APP" "$STAGE/disk/VibeNotch.app"
ln -s /Applications "$STAGE/disk/Applications"
if $PREVIEW; then
  cat > "$STAGE/disk/READ ME.txt" <<'TEXT'
Vibe Notch local preview

This build is for local validation. It is ad-hoc signed and not notarized.
It is not the public beta download. Do not publish it as a Gatekeeper-ready app.
The production release process requires full tests, Developer ID, and notarization.
TEXT
fi
if $UNSIGNED_BETA; then
  cat > "$STAGE/disk/READ ME.txt" <<'TEXT'
Vibe Notch unsigned beta

This beta is ad-hoc signed, not Developer ID signed or notarized by Apple.
macOS may block first launch because Apple cannot verify the developer.
Download only from the official Vibe Notch website and verify the SHA-256 checksum.
If you are uncomfortable with this limitation, wait for a signed release.

Requires Apple Silicon and macOS 14 or newer. Drag VibeNotch.app to Applications.
Source code and license notices accompany this release. Report issues without
including private prompts, paths, credentials, or agent configuration files.
TEXT
fi
DMG="$DIST/$NAME.dmg"
hdiutil create -volname "Vibe Notch" -srcfolder "$STAGE/disk" -ov -format UDZO "$DMG" >/dev/null
if ! $PREVIEW && ! $UNSIGNED_BETA; then
  codesign --timestamp --sign "$IDENTITY" "$DMG"
  notarize "$DMG" "$DIST/$NAME-dmg-notary.json"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi
if ! $PREVIEW; then
  git archive --format=tar.gz --prefix="VibeNotch-$VERSION/" --output="$DIST/$NAME-source.tar.gz" HEAD
fi
python3 scripts/release-metadata.py "$DMG" --version "$VERSION" --preview "$PREVIEW" --unsigned-beta "$UNSIGNED_BETA"
echo "Built $DMG"
if $PREVIEW; then echo "Not published. Public signing, notarization, and fresh-machine validation remain required."; fi
