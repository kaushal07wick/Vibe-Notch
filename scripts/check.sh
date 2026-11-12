#!/usr/bin/env bash
# The production gate uses the actual XCTest suite. No fallback reports it green.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/swift-env.sh"
cd "$ROOT"
for script in scripts/*.sh; do bash -n "$script"; done
plutil -lint Resources/Info.plist Resources/VibeNotch.entitlements
python3 -m unittest discover -s Tests/ReleaseTests -p 'test_*.py'
python3 -m unittest discover -s Tests -p 'test_codex_reply.py' -v
vn_swift build
vn_swift test
