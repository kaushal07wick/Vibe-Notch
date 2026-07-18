#!/usr/bin/env bash
# Assemble VibeNotch.app from the SwiftPM build products. No Xcode required.
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.build/$CONFIG"
APP="$ROOT/.build/VibeNotch.app"

swift build -c "$CONFIG" --product VibeNotch
swift build -c "$CONFIG" --product vibenotch-hook

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"
cp "$BIN/VibeNotch" "$APP/Contents/MacOS/VibeNotch"
cp "$BIN/vibenotch-hook" "$APP/Contents/Helpers/vibenotch-hook"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc sign so Gatekeeper/TCC treats it as a stable, signed app.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "warning: codesign failed (unsigned build)"

echo "Built $APP"
