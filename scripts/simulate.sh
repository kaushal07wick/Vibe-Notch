#!/usr/bin/env bash
# Trigger Vibe Notch states without a real Claude session — feeds canned hook
# JSON straight to the hook binary, exercising the full hook → socket → notch path.
#
# Usage: scripts/simulate.sh [bash|edit|webfetch|notify|stop|codex]
#   The three permission events BLOCK until you click Approve/Deny (as a real
#   session would) and print the decision JSON the agent would receive.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${VN_HOOK:-$HOME/.vibenotch/bin/vibenotch-hook}"
[ -x "$HOOK" ] || HOOK="$ROOT/.build/debug/vibenotch-hook"
[ -x "$HOOK" ] || { echo "hook binary not found — run scripts/bundle.sh first"; exit 1; }

claude() { echo "$1" | "$HOOK" --source claude; }

case "${1:-bash}" in
  bash)     claude '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf node_modules && pnpm install"},"cwd":"'"$PWD"'","session_id":"sim-bash"}' ;;
  edit)     claude '{"hook_event_name":"PermissionRequest","tool_name":"Edit","tool_input":{"file_path":"src/NotchPanelController.swift"},"cwd":"'"$PWD"'","session_id":"sim-edit"}' ;;
  webfetch) claude '{"hook_event_name":"PermissionRequest","tool_name":"WebFetch","tool_input":{"url":"https://api.github.com/repos/anthropics/claude-code"},"cwd":"'"$PWD"'","session_id":"sim-web"}' ;;
  notify)   claude '{"hook_event_name":"Notification","message":"Claude is waiting for your input","cwd":"'"$PWD"'","session_id":"sim-n"}' ;;
  stop)     claude '{"hook_event_name":"Stop","cwd":"'"$PWD"'","session_id":"sim-s"}' ;;
  codex)    "$HOOK" --source codex '{"type":"agent-turn-complete","last-assistant-message":"Refactored the parser and added tests.","cwd":"'"$PWD"'"}' ;;
  *)        echo "unknown state: $1 (try: bash edit webfetch notify stop codex)"; exit 1 ;;
esac
