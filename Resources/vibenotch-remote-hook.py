#!/usr/bin/env python3
"""Vibe Notch remote hook client.

Runs on an SSH server next to a coding agent. Speaks the vibe-notch line-JSON
protocol over the Unix socket that the Mac forwards in (ssh -R). Fail-open:
if the tunnel is down, the agent proceeds with its own permission flow.

  python3 vibenotch-hook.py --install claude   # wire hooks into ~/.claude
  (hooks then invoke: python3 vibenotch-hook.py --source claude)
"""
import json
import os
import socket
import sys

SOCK = os.environ.get("VIBENOTCH_SOCKET", os.path.expanduser("~/.vibenotch/vibenotch.sock"))
HOST = os.uname().nodename.split(".")[0]

EVENTS = [
    ("PermissionRequest", 86400), ("Notification", None), ("Stop", None),
    ("SessionStart", None), ("UserPromptSubmit", None), ("PreToolUse", None),
    ("PostToolUse", None), ("SessionEnd", None),
]


def send(msg, wait):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect(SOCK)
        s.sendall((json.dumps(msg) + "\n").encode())
        if not wait:
            s.close()
            return None
        s.settimeout(86400)
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(4096)
            if not chunk:
                return None
            buf += chunk
        return json.loads(buf.split(b"\n", 1)[0])
    except Exception:
        return None


def install(agent):
    path = os.path.expanduser(f"~/.{agent}/settings.json")
    me = os.path.abspath(__file__)
    cmd = f"/bin/sh -c '[ -f {me} ] && python3 {me} --source {agent} ; exit 0'"
    try:
        settings = json.load(open(path))
    except Exception:
        settings = {}
    hooks = settings.setdefault("hooks", {})
    for name, timeout in EVENTS:
        groups = hooks.setdefault(name, [])
        if any("vibenotch" in h.get("command", "")
               for g in groups for h in g.get("hooks", [])):
            continue
        hook = {"type": "command", "command": cmd}
        if timeout:
            hook["timeout"] = timeout
        groups.append({"matcher": "*", "hooks": [hook]})
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(settings, open(path, "w"), indent=2)
    print(f"vibenotch hooks installed into {path}")


def first_string(d, keys):
    for k in keys:
        v = d.get(k)
        if isinstance(v, str) and v:
            return v
    return None


def main():
    args = sys.argv[1:]
    if "--install" in args:
        install(args[args.index("--install") + 1])
        return
    source = args[args.index("--source") + 1] if "--source" in args else "claude"
    try:
        obj = json.load(sys.stdin)
    except Exception:
        obj = {}
    event = obj.get("hook_event_name", "Unknown")
    ti = obj.get("tool_input") or {}
    sid = obj.get("session_id")
    base = {
        "source": source,
        "event": event,
        "tool": obj.get("tool_name"),
        "detail": first_string(ti, ("command", "file_path", "path", "url", "pattern")),
        "cwd": obj.get("cwd"),
        "host": HOST,
        "sessionId": f"{HOST}:{sid}" if sid else None,
    }

    if event == "PermissionRequest":
        base.update(type="request", commandDescription=ti.get("description"))
        reply = send(base, wait=True)
        decision = (reply or {}).get("decision")
        behavior = None
        if decision in ("allow", "alwaysAllow", "bypass"):
            behavior = "allow"
        elif decision == "deny":
            behavior = "deny"
        if behavior:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": behavior}}}))
        return  # no decision → agent's own flow (fail-open)

    if event == "PostToolUse":
        tr = obj.get("tool_response")
        out = tr if isinstance(tr, str) else first_string(tr or {}, ("stdout", "output", "content"))
        base["detail"] = (out or "")[:1200] or None
    elif event == "Notification":
        base["detail"] = obj.get("message")
    elif event not in ("Stop", "SessionStart", "UserPromptSubmit", "SessionEnd",
                       "PreToolUse", "SubagentStart", "SubagentStop"):
        return
    base["type"] = "notify"
    send(base, wait=False)


if __name__ == "__main__":
    main()
