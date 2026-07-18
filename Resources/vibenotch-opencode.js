// Vibe Notch plugin for OpenCode.
// Bridges OpenCode events to the notch app over its Unix socket.
// Installed to ~/.config/opencode/plugins/vibenotch.js — fail-open throughout.
import { connect } from "net";
import { homedir } from "os";

const SOCKET = `${process.env.HOME || homedir()}/.vibenotch/run/vibenotch.sock`;

const send = (msg) =>
  new Promise((resolve) => {
    try {
      const sock = connect({ path: SOCKET }, () => sock.end(JSON.stringify(msg) + "\n"));
      sock.on("error", () => resolve(false));
      sock.on("close", () => resolve(true));
      sock.setTimeout(3000, () => { sock.destroy(); resolve(false); });
    } catch { resolve(false); }
  });

// Open a request, block until the notch replies one JSON line ({decision,...}).
const request = (msg, timeoutMs = 86_400_000) =>
  new Promise((resolve) => {
    try {
      const sock = connect({ path: SOCKET }, () => sock.write(JSON.stringify(msg) + "\n"));
      let buf = "";
      sock.on("data", (chunk) => {
        buf += chunk.toString();
        const nl = buf.indexOf("\n");
        if (nl >= 0) {
          sock.destroy();
          try { resolve(JSON.parse(buf.slice(0, nl))); } catch { resolve(null); }
        }
      });
      sock.on("error", () => resolve(null));
      sock.on("end", () => resolve(null));
      sock.setTimeout(timeoutMs, () => { sock.destroy(); resolve(null); });
    } catch { resolve(null); }
  });

export default async ({ serverUrl }) => {
  const sessionCwd = new Map();
  const base = { source: "opencode" };
  const title = (s) => (s ? String(s).slice(0, 140) : undefined);

  const notify = (event, sessionID, extra = {}) =>
    send({ type: "notify", event, sessionId: sessionID,
           cwd: sessionCwd.get(sessionID), ...base, ...extra });

  return {
    event: async ({ event }) => {
      try {
        const t = event.type;
        const p = event.properties || {};

        if (t === "session.created" && p.id) {
          if (p.directory) sessionCwd.set(p.id, p.directory);
          return notify("SessionStart", p.id);
        }
        if (t === "session.deleted" && p.id) return notify("SessionEnd", p.id);
        if (t === "session.idle" && p.sessionID) return notify("Stop", p.sessionID);
        if (t === "message.updated" && p.info?.sessionID && p.info?.role === "user") {
          return notify("UserPromptSubmit", p.info.sessionID,
                        { userMessage: title(p.info?.summary) });
        }
        if (t === "message.part.updated" && p.part?.sessionID && p.part?.type === "tool") {
          const st = p.part.state?.status;
          const tool = (p.part.tool || "Tool");
          const input = p.part.state?.input;
          const detail = typeof input === "string" ? input : JSON.stringify(input || {}).slice(0, 300);
          if (st === "running" || st === "pending")
            return notify("PreToolUse", p.part.sessionID, { tool, detail });
          if (st === "completed" || st === "error")
            return notify("PostToolUse", p.part.sessionID, { tool });
          return;
        }

        // Permission — block on the notch, then answer OpenCode's server.
        if (t === "permission.asked" && p.id && p.sessionID) {
          const patterns = p.patterns || [];
          const tool = (p.permission || "tool");
          const reply = await request({
            type: "request", event: "PermissionRequest", sessionId: p.sessionID,
            cwd: sessionCwd.get(p.sessionID), tool,
            detail: patterns.join(" && ") || tool, ...base,
          });
          if (!reply?.decision) return; // fail-open: OpenCode's own prompt stands
          const allow = !["deny", "ask"].includes(reply.decision);
          try {
            await fetch(`${serverUrl}/permission/${p.id}/reply`, {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ reply: allow ? "once" : "reject" }),
            });
          } catch {}
          return;
        }
      } catch {
        // Fail open — never break OpenCode if the notch app is away.
      }
    },
  };
};
