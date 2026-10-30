#!/usr/bin/env bash
# Assemble VibeNotch.app from the SwiftPM build products. No Xcode required.
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.build/$CONFIG"
APP="$ROOT/.build/VibeNotch.app"

swift build -c "$CONFIG" --product VibeNotch
swift build -c "$CONFIG" --product vibenotch-hook
swift build -c "$CONFIG" --product VibeNotchCLI

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"
cp "$BIN/VibeNotch" "$APP/Contents/MacOS/VibeNotch"
cp "$BIN/vibenotch-hook" "$APP/Contents/Helpers/vibenotch-hook"
cp "$BIN/VibeNotchCLI" "$APP/Contents/Helpers/vibenotch"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# CFBundleVersion must increase every build — it was hardcoded to 1, so macOS
# and any updater saw every release as the same build.
plutil -replace CFBundleVersion -string \
  "$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true
plutil -replace CFBundleIconFile -string AppIcon "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/Fonts"
cp "$ROOT/Resources/Fonts/"*.otf "$APP/Contents/Resources/Fonts/" 2>/dev/null || true
mkdir -p "$APP/Contents/Resources/AgentIcons"
cp "$ROOT/Resources/AgentIcons/"*.png "$APP/Contents/Resources/AgentIcons/" 2>/dev/null || true
cp "$ROOT/Resources/"*.js "$APP/Contents/Resources/" 2>/dev/null || true
cp "$ROOT/Resources/"*.py "$APP/Contents/Resources/" 2>/dev/null || true
cp "$ROOT/Resources/nowplaying.pl" "$APP/Contents/Resources/"
# now-playing bridge: loaded by /usr/bin/perl, which macOS still lets read system media
clang -dynamiclib -fobjc-arc -O2 -framework Foundation "$ROOT/Resources/NowPlayingBridge.m" \
  -o "$APP/Contents/Helpers/libvnnowplaying.dylib"

# Ad-hoc sign with a designated requirement pinned to the bundle id. Plain ad-hoc signing
# makes the requirement a cdhash, which changes every build, so macOS privacy (TCC) saw
# each rebuild as a new app and re-asked for Calendar, Accessibility and Automation.
codesign --force --deep --sign - \
  --requirements '=designated => identifier "com.kaushalchoudhary.vibenotch"' \
  "$APP" >/dev/null 2>&1 || echo "warning: codesign failed (unsigned build)"

echo "Built $APP"
