#!/usr/bin/env bash
# Build an Apple Silicon app from a clean checkout, with no dependency downloads.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/swift-env.sh"
CONFIG="${1:-debug}"
case "$CONFIG" in debug|release) ;; *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;; esac
[ "$(uname -m)" = arm64 ] || { echo "Vibe Notch currently supports Apple Silicon builds only." >&2; exit 1; }
cd "$ROOT"
for product in VibeNotch vibenotch-hook VibeNotchCLI; do vn_swift build -c "$CONFIG" --product "$product"; done
BIN="$(vn_swift build -c "$CONFIG" --show-bin-path)"
APP="$ROOT/.build/VibeNotch.app"
STAGE_ROOT="$(mktemp -d "$ROOT/.build/VibeNotch.bundle.XXXXXX")"
STAGE="$STAGE_ROOT/VibeNotch.app"
trap 'rm -rf "$STAGE_ROOT"' EXIT
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Helpers" "$STAGE/Contents/Resources/Fonts" "$STAGE/Contents/Resources/AgentIcons" "$STAGE/Contents/Resources/Licenses"
cp "$BIN/VibeNotch" "$STAGE/Contents/MacOS/VibeNotch"
cp "$BIN/vibenotch-hook" "$STAGE/Contents/Helpers/vibenotch-hook"
cp "$BIN/VibeNotchCLI" "$STAGE/Contents/Helpers/vibenotch"
cp "$ROOT/Resources/Info.plist" "$STAGE/Contents/Info.plist"
BUILD="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD)}"
[[ "$BUILD" =~ ^[1-9][0-9]{0,3}$ ]] || { echo "BUILD_NUMBER must be an integer from 1 to 9999." >&2; exit 1; }
plutil -replace CFBundleVersion -string "$BUILD" "$STAGE/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$STAGE/Contents/Resources/"
cp "$ROOT/Resources/Fonts/"*.otf "$STAGE/Contents/Resources/Fonts/"
cp "$ROOT/Resources/Fonts/LICENSE.txt" "$STAGE/Contents/Resources/Licenses/DepartureMono-OFL.txt"
cp "$ROOT/LICENSE" "$STAGE/Contents/Resources/Licenses/VibeNotch-GPL-3.0.txt"
cp "$ROOT/Vendor/DynamicNotchKit/LICENSE" "$STAGE/Contents/Resources/Licenses/DynamicNotchKit-MIT.txt"
cp "$ROOT/Resources/THIRD_PARTY_NOTICES.txt" "$STAGE/Contents/Resources/"
cp "$ROOT/Resources/AgentIcons/"*.png "$STAGE/Contents/Resources/AgentIcons/"
cp "$ROOT/Resources/"*.js "$ROOT/Resources/"*.py "$ROOT/Resources/nowplaying.pl" "$STAGE/Contents/Resources/"
clang -dynamiclib -fobjc-arc -O2 -arch arm64 -mmacosx-version-min=14.0 -framework Foundation "$ROOT/Resources/NowPlayingBridge.m" -o "$STAGE/Contents/Helpers/libvnnowplaying.dylib"
for binary in "$STAGE/Contents/Helpers/"* "$STAGE/Contents/MacOS/VibeNotch"; do codesign --force --sign - "$binary"; done
codesign --force --sign - --requirements '=designated => identifier "com.kaushalchoudhary.vibenotch"' "$STAGE"
codesign --verify --deep --strict "$STAGE"
rm -rf "$APP"
mv "$STAGE" "$APP"
echo "Built $APP"
