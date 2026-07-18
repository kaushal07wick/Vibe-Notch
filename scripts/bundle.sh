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
mkdir -p "$APP/Contents/Resources"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true
plutil -replace CFBundleIconFile -string AppIcon "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/Fonts"
cp "$ROOT/Resources/Fonts/"*.otf "$APP/Contents/Resources/Fonts/" 2>/dev/null || true
cp "$ROOT/Resources/"*.js "$APP/Contents/Resources/" 2>/dev/null || true
cp "$ROOT/Resources/"*.py "$APP/Contents/Resources/" 2>/dev/null || true

# Ad-hoc sign so Gatekeeper/TCC treats it as a stable, signed app.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "warning: codesign failed (unsigned build)"

echo "Built $APP"
