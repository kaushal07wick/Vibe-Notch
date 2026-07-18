# Vibe Notch — v1 Design

Open-source, native-macOS alternative to Vibe Island: a panel **in the Mac notch**
that monitors CLI AI coding agents, approves/denies their permission requests, and
jumps you back to the terminal they run in.

- **Date:** 2026-07-18
- **Stack:** Swift / SwiftUI, Apple Silicon, no Electron
- **v1 agents:** Claude Code (full approve/deny) + Codex (notifications only)
- **v1 terminals:** iTerm2, Terminal.app, Ghostty

## Goal & non-goals

**Goal:** the smallest slice that captures the core magic, architected so more agents
and features bolt on without rework — a notch panel that surfaces Claude Code
permission requests and lets you approve/deny from the notch, surfaces Codex
turn-complete/waiting notifications, and jumps to the source terminal.

**Non-goals in v1** (see roadmap): Codex GUI approval, Markdown plan preview, sound
alerts, other agents, usage/quota tracking, SSH remote, external-display floating bar,
tmux/split-pane precision jump.

## Why the two agents differ

- **Claude Code** exposes a **`PreToolUse` hook** that can *block up to 600s* and return
  `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision":
  "allow"|"deny"|"ask", ...}}` on stdout (exit 0). That is a real blocking
  GUI-approval channel.
- **Codex** exposes only **`notify`** — a program run with a single JSON argv on
  `agent-turn-complete`. It is notification-only; Codex approvals live in its TUI.
  So v1 gives Codex notifications + jump, not approve/deny.

## Architecture

Six components. The `AgentAdapter` protocol is the seam that makes "add an agent" a
small change.

### 1. `VibeNotch.app` — SwiftUI menu-bar agent
- `LSUIElement` (no Dock icon), menu-bar status item.
- A borderless, **non-activating** `NSPanel` (`.nonactivatingPanel`,
  `.canJoinAllSpaces`, high window level) pinned centered under the notch using the
  active screen's `safeAreaInsets` / notch geometry. Falls back to a top-center bar on
  notchless screens (v1 supports notch Macs; floating bar is P4-polish but the same
  window works).
- Renders a **queue** of `AgentEvent`s: pending approval cards (Approve / Deny / Ask +
  Jump) and notification cards (message + Jump). Newest on top; approvals sort above
  notifications.

### 2. Local IPC server (inside the app)
- **Unix domain socket** at `~/.vibenotch/sock`. Local-only, no TCP port, no auth
  surface. Created on launch, removed on quit; stale socket cleaned on start.
- Line-delimited JSON protocol. Two message kinds from clients:
  - `request` — needs a decision; the connection **stays open** until the user acts.
    Server replies `{"decision": "allow"|"deny"|"ask", "reason": "..."}`.
  - `notify` — fire-and-forget; server acks and closes.

### 3. `vibenotch-hook` — CLI binary (shipped in the bundle)
One small binary, mode by flag/argv:
- **Claude Code PreToolUse** (default stdin mode): read hook JSON from stdin → open
  socket → send `request` → **block ≤590s** (under the 600s cap; on timeout or socket
  error, emit `defer` so Claude's normal flow still works — never hang the agent) →
  translate the socket reply into the `hookSpecificOutput` JSON → stdout, exit 0.
- **Claude Code Notification/Stop** hooks: send `notify`, exit 0.
- **Codex notify** (`--codex`): argv[1] is the JSON payload → send `notify` → exit 0.

Fail-open everywhere: if the app isn't running or the socket is gone, the hook must
never block the agent — it returns `defer` (Claude) / exits 0 (Codex).

### 4. `AgentAdapter` protocol — the extensibility seam
```
protocol AgentAdapter {
    var id: String { get }                      // "claude-code", "codex"
    func parse(_ raw: RawPayload) -> AgentEvent  // → common model
    func install() throws                        // edit agent config, with backup
    func uninstall() throws                       // restore backup
    var supportsApproval: Bool { get }            // Claude: true, Codex: false
}
```
- `ClaudeCodeAdapter.install()` merges hook entries into `~/.claude/settings.json`
  (PreToolUse → `vibenotch-hook`; Notification/Stop → `vibenotch-hook`), backing up
  first. Idempotent.
- `CodexAdapter.install()` sets `notify = ["<path>/vibenotch-hook", "--codex"]` in
  `~/.codex/config.toml`, backing up first. Idempotent. Note: `notify` is single-slot —
  if the user already has a notify program, we chain-call it (store the previous value
  and forward), or warn. v1: back up + warn if occupied, offer to chain.

### 5. `AgentEvent` — common model
```
struct AgentEvent {
    let id: UUID
    let agentId: String              // "claude-code" | "codex"
    let kind: Kind                   // .approval | .notification
    let title: String                // e.g. "Bash", "Codex waiting"
    let detail: String?              // command / file path / last-assistant-message
    let cwd: String?
    let terminal: TerminalContext?   // for jump: app + tty/session if resolvable
    let createdAt: Date
}
```

### 6. `TerminalJumper`
- `osascript`/AppleScript to focus the source terminal, resolved from `cwd`/TTY when
  possible:
  - **iTerm2** & **Terminal.app**: real AppleScript — activate + select the
    tab/session matching the tty.
  - **Ghostty**: thin scripting — v1 does best-effort `activate` of the app.
    `ponytail:` Ghostty precision (window/tab targeting) deferred to P4.
- Which terminal launched the agent is inferred from the process tree /
  `TERM_PROGRAM`-style env passed through the hook payload when available; else the
  user's configured default terminal.

### 7. First-run setup
- On first launch: detect installed agents & terminals, show a short onboarding,
  call each adapter's `install()` (with visible backup paths), let the user pick a
  default terminal. Re-runnable from the menu-bar menu ("Reconnect agents").
- Menu also offers `uninstall()` (restore backups) for clean removal.

## Data flow

**Claude Code approve/deny**
```
Claude Code needs permission
  → PreToolUse hook runs `vibenotch-hook` (stdin JSON)
  → socket `request` → app enqueues → notch card (tool + command/path)
  → user taps Approve / Deny / Ask
  → app replies over socket
  → hook prints hookSpecificOutput JSON, exit 0
  → Claude Code proceeds
```

**Codex notification**
```
Codex finishes a turn / waits
  → notify runs `vibenotch-hook --codex <json>`
  → socket `notify` → notch card ("Codex waiting" + last message + Jump)
```

## Error handling
- **Hook fail-open:** app down / socket missing / timeout → Claude gets `defer`, Codex
  exits 0. The agent is never blocked by Vibe Notch.
- **Config edits are reversible:** every `install()` backs up the target file first;
  `uninstall()` restores it. Idempotent so re-running setup can't duplicate entries.
- **Codex `notify` collision:** detect an existing `notify`; back up and offer to chain
  the previous program rather than silently clobbering it.
- **Stale socket:** removed and recreated on launch.

## Testing
- `vibenotch-hook` decision translation: unit test that a mocked socket reply →
  correct `hookSpecificOutput` JSON, and that timeout/socket-error → `defer`. One
  runnable self-check is required here (money/security-adjacent: a wrong translation
  could auto-approve a destructive command).
- `AgentAdapter.install()/uninstall()` round-trip on a temp config file: install then
  uninstall yields the original bytes; install is idempotent.
- IPC: a request stays open until a decision, then returns it; a notify acks and closes.

## Roadmap (context for the seams above)
- **P2:** Codex full approve/deny (app-server / PTY harness), Markdown plan preview,
  8-bit sound alerts.
- **P3:** more agents (Gemini CLI, Cursor, Copilot…), usage/quota tracking.
- **P4:** SSH remote monitoring, external-display floating bar, tmux/split-pane
  precision jump, Ghostty precision targeting.

## Open decisions deferred (not blocking v1)
- Packaging/signing (unsigned local build vs notarized DMG) — decide before release.
- Whether to ship `vibenotch-hook` as a separate thin binary or a symlinked mode of the
  app executable — implementation detail, pick during build.
