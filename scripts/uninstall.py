#!/usr/bin/env python3
"""Remove only Vibe Notch entries, with backups; safe to exercise against a fixture home."""
import argparse
import copy
import json
import os
from pathlib import Path
import shlex
import shutil
import stat
import tempfile
import uuid


def managed(command):
    return isinstance(command, str) and "vibenotch-hook" in command


def remove_hooks(root, flat=False):
    result = copy.deepcopy(root)
    hooks = result.get("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError("hooks must be an object")
    for event, groups in list(hooks.items()):
        if not isinstance(groups, list):
            raise ValueError("hook groups must be arrays")
        kept = []
        for group in groups:
            if not isinstance(group, dict):
                raise ValueError("hook entries must be objects")
            if flat:
                if not managed(group.get("command")):
                    kept.append(group)
            elif "hooks" not in group:
                kept.append(group)
            else:
                entries = group["hooks"]
                if not isinstance(entries, list) or not all(isinstance(h, dict) for h in entries):
                    raise ValueError("hooks must contain objects")
                remaining = [h for h in entries if not managed(h.get("command"))]
                if len(remaining) == len(entries):
                    kept.append(group)
                elif remaining:
                    group["hooks"] = remaining
                    kept.append(group)
        if kept:
            hooks[event] = kept
        else:
            hooks.pop(event, None)
    if not hooks:
        result.pop("hooks", None)
    return result


def original_statusline(home):
    directory = home / ".vibenotch/bin"
    saved = directory / "statusline-original.json"
    if saved.exists():
        original = json.loads(saved.read_text())
        if original is not None and not isinstance(original, dict):
            raise ValueError("invalid saved status line")
        return original
    script = directory / "statusline.sh"
    if script.exists():
        for line in script.read_text().splitlines():
            if line.startswith("ORIG="):
                values = shlex.split(line[5:])
                if len(values) != 1:
                    raise ValueError("cannot recover the original status line")
                return {"type": "command", "command": values[0]} if values[0] else None
    return None


def plan(home):
    changes = []

    def json_change(path, flat=False, plugin=False):
        if not path.exists():
            return
        before = path.read_bytes()
        root = json.loads(before)
        if not isinstance(root, dict):
            raise ValueError(str(path) + " must contain an object")
        after = remove_hooks(root, flat=flat)
        status = after.get("statusLine")
        if isinstance(status, dict) and str(home / ".vibenotch/bin/statusline.sh") in status.get("command", ""):
            restored = original_statusline(home)
            if restored is None:
                after.pop("statusLine", None)
            else:
                after["statusLine"] = restored
        if plugin and "plugin" in after:
            if not isinstance(after["plugin"], list):
                raise ValueError("plugin must be an array")
            after["plugin"] = [p for p in after["plugin"] if not (isinstance(p, str) and p.endswith("/plugins/vibenotch.js"))]
            if not after["plugin"]:
                after.pop("plugin")
        if after != root:
            changes.append((path, before, (json.dumps(after, indent=2, ensure_ascii=False) + "\n").encode()))

    for directory in [".claude", ".qwen", ".factory", ".gemini", ".qoder", ".codebuddy"]:
        json_change(home / directory / "settings.json")
    json_change(home / ".codex/hooks.json")
    json_change(home / ".cursor/hooks.json", flat=True)
    json_change(home / ".config/opencode/opencode.json", plugin=True)
    for directory in [".codex", ".kimi"]:
        path = home / directory / "config.toml"
        if not path.exists():
            continue
        before = path.read_bytes()
        text = before.decode()
        output, skipping = [], False
        for line in text.splitlines(keepends=True):
            if directory == ".kimi" and line.strip() == "# vibenotch: managed hook — do not edit":
                skipping = True
                continue
            if skipping:
                if not line.strip():
                    skipping = False
                continue
            if directory == ".codex" and line.lstrip().startswith("notify") and managed(line):
                continue
            output.append(line)
        after = "".join(output).encode()
        if after != before:
            changes.append((path, before, after))
    plugin = home / ".config/opencode/plugins/vibenotch.js"
    if plugin.exists():
        changes.append((plugin, plugin.read_bytes(), None))
    return changes


def apply(changes):
    for path, before, _ in changes:
        if path.read_bytes() != before:
            raise RuntimeError(str(path) + " changed during removal; retry after reviewing it")
    suffix = ".vibenotch-uninstall-" + uuid.uuid4().hex + ".bak"
    for path, _, _ in changes:
        shutil.copy2(path, str(path) + suffix)
    for path, _, after in changes:
        if after is None:
            path.unlink()
            continue
        mode = stat.S_IMODE(path.stat().st_mode)
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
            temporary = Path(output.name)
            output.write(after)
        try:
            os.chmod(temporary, mode)
            os.replace(temporary, path)
        finally:
            if temporary.exists():
                temporary.unlink()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--home", type=Path, default=Path.home(), help="Home directory; use a temporary fixture for tests")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--keep-data", action="store_true")
    args = parser.parse_args()
    changes = plan(args.home)
    for path, _, _ in changes:
        print(("Would clean " if args.dry_run else "Cleaning ") + str(path))
    if not args.dry_run:
        apply(changes)
        data = args.home / ".vibenotch"
        if not args.keep_data and data.exists():
            shutil.rmtree(data)
        print("Removed Vibe Notch hooks. Original configs have dated backups.")


if __name__ == "__main__":
    main()
