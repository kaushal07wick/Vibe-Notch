#!/usr/bin/env bash
# Cleanly remove Vibe Notch: hooks from every agent config (restoring nothing
# else), the status line wrapper, and ~/.vibenotch. The app itself is just
# dragged to the Trash.
set -uo pipefail

echo "Removing Vibe Notch hooks from agent configs…"
python3 - <<'PY'
import json, os, re

home = os.path.expanduser("~")

def clean_json_hooks(path):
    try:
        s = json.load(open(path))
    except Exception:
        return
    changed = False
    hooks = s.get("hooks", {})
    for ev in list(hooks):
        kept = [g for g in hooks[ev]
                if not any("vibenotch" in h.get("command", "") for h in g.get("hooks", []))]
        if len(kept) != len(hooks[ev]):
            changed = True
            if kept: hooks[ev] = kept
            else: del hooks[ev]
    if not hooks and "hooks" in s: del s["hooks"]
    # status line wrapper
    if "vibenotch" in (s.get("statusLine", {}) or {}).get("command", ""):
        del s["statusLine"]; changed = True
    if changed:
        json.dump(s, open(path, "w"), indent=2)
        print("  cleaned", path)

for d in (".claude", ".qwen", ".qoder", ".factory", ".codebuddy", ".gemini"):
    p = f"{home}/{d}/settings.json"
    if os.path.exists(p): clean_json_hooks(p)

# Cursor hooks.json
p = f"{home}/.cursor/hooks.json"
if os.path.exists(p):
    try:
        s = json.load(open(p))
        hooks = s.get("hooks", {})
        changed = False
        for ev in list(hooks):
            kept = [e for e in hooks[ev] if "vibenotch" not in e.get("command", "")]
            if len(kept) != len(hooks[ev]):
                changed = True
                if kept: hooks[ev] = kept
                else: del hooks[ev]
        if changed:
            json.dump(s, open(p, "w"), indent=2); print("  cleaned", p)
    except Exception: pass

# Codex notify + Kimi managed blocks
for d, strip_blocks in ((".codex", False), (".kimi", True)):
    p = f"{home}/{d}/config.toml"
    if not os.path.exists(p): continue
    text = open(p).read()
    if "vibenotch" not in text: continue
    if strip_blocks:
        out, skip = [], False
        for line in text.split("\n"):
            if line.strip() == "# vibenotch: managed hook — do not edit": skip = True; continue
            if skip:
                if not line.strip(): skip = False
                continue
            out.append(line)
        text = "\n".join(out)
    else:
        text = "\n".join(l for l in text.split("\n") if "vibenotch" not in l)
    open(p, "w").write(text); print("  cleaned", p)

# OpenCode plugin
p = f"{home}/.config/opencode/opencode.json"
if os.path.exists(p):
    try:
        s = json.load(open(p))
        plugins = [x for x in s.get("plugin", []) if "vibenotch" not in x]
        if plugins != s.get("plugin", []):
            if plugins: s["plugin"] = plugins
            else: s.pop("plugin", None)
            json.dump(s, open(p, "w"), indent=2); print("  cleaned", p)
    except Exception: pass
os.path.exists(f"{home}/.config/opencode/plugins/vibenotch.js") and os.remove(f"{home}/.config/opencode/plugins/vibenotch.js")
PY

echo "Removing ~/.vibenotch…"
rm -rf "$HOME/.vibenotch"
echo "Done. Backups (*.vibenotch.bak) were left beside each config."
