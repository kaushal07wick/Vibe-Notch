#!/usr/bin/env bash
# Run deliberately; this removes Vibe Notch's data after restoring agent configs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ "${1:-}" != --dry-run ]; then
  osascript -e 'if application id "com.kaushalchoudhary.vibenotch" is running then tell application id "com.kaushalchoudhary.vibenotch" to quit'
fi
python3 "$ROOT/scripts/uninstall.py" "$@"
