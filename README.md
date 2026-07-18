<div align="center">

<img src="docs/assets/icon.png" width="128" alt="Vibe Notch icon">

# Vibe Notch

**Your AI coding agents, living in the Mac notch.**

Approve permissions, watch sessions, reply, panic-stop, and resume old runs —
without leaving whatever you're doing.

[![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](Package.swift)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](#requirements)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-6FB982.svg)](#contributing)

<img src="docs/assets/sessions.png" width="640" alt="Vibe Notch expanded panel showing two live Claude sessions">

</div>

---

Claude Code asks *"can I run this command?"* — and the prompt is buried in a
terminal tab behind six other windows. Vibe Notch puts that moment where your
eyes already are: the notch. Glance, approve, keep working.

Native Swift + SwiftUI. **No Electron. No network. No accounts.** Everything
runs on your Mac.

## Highlights

🔔 **Approve from the notch** — permission cards with the full command, its
diff (for file edits), and Deny / Allow / Bypass. Dangerous commands
(`rm -rf`, `sudo`, `curl | sh`…) require **hold-to-approve** — no reflexive
misclicks.

👀 **Live session board** — every agent session with its task, your last
message, what it's running right now, a rolling console mirror, git branch,
and token usage.

⚡ **Act without switching** — jump to the exact terminal tab (`^G`), type a
reply straight into the agent's pane, or **panic-stop** a runaway command with
a real `^C`.

🕘 **Session history** — click the clock, see past Claude sessions, click one:
a terminal opens running `claude --resume <id>` for you.

🔍 **⌘K palette** — search across active sessions, history, and actions from
one field.

🛡️ **Guardrails** — screen-share guard queues cards silently while you're
presenting; smart suppression skips the popup when the agent's terminal is
already frontmost; per-project policies can lock strict repos to allow-once;
a safe-list auto-approves harmless reads (`git status`, `ls`, …).

📈 **Usage & escalation** — Claude 5h/7d rate-limit windows in the header;
unanswered requests re-chime, badge the menu bar, and (optionally) ping your
phone via [ntfy](https://ntfy.sh).

🧪 **Labs** — localhost web dashboard, notch-over-lock-screen, multi-Mac
monitoring over SSH, and a scriptable CLI
(`vibenotch list|approve|deny|send|interrupt`).

## Supported agents

| Agent | Approvals | Activity | Config |
|---|:--:|:--:|---|
| Claude Code | ✅ | ✅ | `~/.claude/settings.json` |
| Codex | ✅ | ✅ | `~/.codex` (hooks) |
| OpenCode | ✅ | ✅ | plugin, `opencode.json` |
| Qwen · Qoder · Droid · CodeBuddy · Kimi | ✅ | ✅ | Claude-schema / TOML |
| Cursor | — | ✅ | `~/.cursor/hooks.json` |
| Gemini CLI | — | ✅ | `~/.gemini/settings.json` |

Detected agents are wired automatically on first launch; toggle any of them
from the menu bar. Every config edit is backed up and reversible.

## Install

### Download

Grab the latest `VibeNotch-x.y.z.dmg` from
[Releases](https://github.com/kaushal07wick/Vibe-Notch/releases), open it, and
drag **VibeNotch** to Applications.

> Builds are currently ad-hoc signed — on first open, right-click →
> **Open** to pass Gatekeeper.

### Build from source

Requires macOS 14+, Apple Silicon, and the Swift 6 toolchain
(`xcode-select --install` is enough — no Xcode IDE needed).

```bash
git clone https://github.com/kaushal07wick/Vibe-Notch.git
cd Vibe-Notch
./scripts/bundle.sh          # → .build/VibeNotch.app
open .build/VibeNotch.app
```

No Dock icon — look for the notch and the menu-bar item. Detected agents
connect automatically.

### Try it without a real agent

```bash
./scripts/simulate.sh bash     # a Bash approval card (blocks until you decide)
./scripts/simulate.sh notify   # a "waiting" session row
```

## How it works

```
 your agent (Claude Code, …)          VibeNotch.app
 ───────────────────────────          ─────────────
  fires a hook ──► vibenotch-hook ──► unix socket ──► notch card
                   (tiny CLI)         ~/.vibenotch/     │ Approve / Deny
  ◄── decision JSON ◄── blocks on ◄── reply ◄──────────┘
```

- The hook is **fail-open**: if the app isn't running, agents behave exactly
  as they would without Vibe Notch. Nothing is ever blocked by us.
- Local Unix socket only — no TCP, no cloud, no telemetry.
- Answer in the terminal instead? The card notices and dismisses itself.

Full architecture notes live in [`docs/specs/`](docs/specs/).

## Keyboard

| Keys | Action |
|---|---|
| `^A` | Approve the front card |
| `^G` | Jump to the session's terminal tab |
| `⌘K` | Command palette (panel focused) |
| `Esc` | Collapse the panel |

## CLI

```bash
~/.vibenotch/bin/vibenotch list                 # sessions + pending, as JSON
~/.vibenotch/bin/vibenotch approve              # approve the front card
~/.vibenotch/bin/vibenotch send <session> "hi"  # type into that session
~/.vibenotch/bin/vibenotch interrupt <session>  # ^C its foreground process
```

Scriptable from Raycast, cron, or another Mac over SSH.

## Privacy & security

- **Local-first, always.** No accounts, no analytics, no outbound requests
  (the single exception: ntfy phone pings, off by default, to a topic you set).
- Approval decisions are yours: rules written by *Always Allow* live in your
  agent's own config; the safe-list and per-project policies are plain JSON
  under `~/.vibenotch/data` you can audit and edit.
- Screen-share guard keeps commands and prompts off your screen while
  presenting.

## Uninstall

Menu bar → toggle each agent off (restores their original configs), quit the
app, then:

```bash
./scripts/uninstall.sh    # or: rm -rf ~/.vibenotch
```

## Contributing

PRs welcome — this is a community rebuild of a great idea, and the codebase is
deliberately small (Swift package, three targets, no Xcode project).

- `swift build && swift test` must stay green (`./scripts/bundle.sh` for the .app)
- One focused change per PR; match the surrounding style
- Agents are added via a single `AgentSpec` — see [`docs/`](docs/) and
  `Sources/VibeNotchCore/AgentSpec.swift`
- UI changes: attach a before/after screenshot

## License

[GPL-3.0](LICENSE) — free forever, improvements stay open.

## Acknowledgments

- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) (MIT) — notch
  window, hover, and morph physics
- [Vibe Island](https://vibeisland.app) — the closed-source original that
  inspired this rebuild; [`open-vibe-island`](https://github.com/search?q=open-vibe-island)
  and [boring.notch](https://github.com/TheBoredTeam/boring.notch) for
  mechanism reference
- Departure Mono for the terminal blocks
