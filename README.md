# Vibe Notch

**A native macOS notch companion for your CLI AI coding agents.**

Vibe Notch lives in your Mac's notch and watches the AI coding agents you run in
the terminal — Claude Code, Codex, Cursor, Gemini CLI, and more. It surfaces their
**permission requests so you can approve or deny right from the notch**, shows live
activity and usage, and jumps you back to the terminal the agent is running in.

Native Swift/SwiftUI, Apple Silicon, **no Electron**. An open-source alternative to
Vibe Island.

> **Status:** v0.1 → v0.2 in progress. Builds and runs from source today. See the
> [roadmap](#roadmap).

<!-- TODO: drop a screenshot / gif of the notch approving a Bash command here -->

---

## Why

CLI coding agents block on permission prompts buried in whichever terminal tab you
last used. Vibe Notch pulls that moment up into the notch — a glanceable, clickable
surface that's always in the same place — and gets you back to the right terminal
in one click. It's **fail-open by design**: if the app isn't running, agents behave
exactly as they normally would.

## Features

- **Approve / Deny from the notch** — Claude Code permission requests appear as cards; your decision is returned to the agent over a local socket.
- **Live activity** — what each session is doing right now (tool, command, last message), per agent.
- **Usage tracking** — Claude 5-hour / 7-day rate-limit windows and Codex quota, as color-coded chips (green → orange ≥70% → red ≥90%).
- **Terminal jump** — click a card to focus the terminal (iTerm2, Terminal.app, Ghostty) the agent runs in.
- **Zero-config** — every detected agent is auto-connected on launch; toggle per-agent from the menu bar.
- **Reversible** — every config edit is backed up; disconnecting restores the original.

### Supported agents

| Agent | Approve / Deny | Notifications | Config file |
|-------|:--:|:--:|-------------|
| Claude Code | ✅ | ✅ | `~/.claude/settings.json` |
| Qwen · Qoder · Droid (Factory) · CodeBuddy | ✅ | ✅ | `~/.<agent>/settings.json` (Claude-schema) |
| Cursor | — | ✅ | `~/.cursor/hooks.json` |
| Gemini CLI | — | ✅ | `~/.gemini/settings.json` |
| Codex | — | ✅ | `~/.codex/config.toml` |

The live registry is `Sources/VibeNotchCore/AgentSpec.swift`. Adding an agent is one
spec + (usually) an existing installer — see [Adding an agent](#adding-an-agent).

## How it works

Vibe Notch is three pieces that talk over a local Unix domain socket — no network,
no TCP port, no auth surface.

```
 AI agent (Claude Code, …)          Vibe Notch.app (menu-bar / notch)
 ─────────────────────────          ────────────────────────────────
  fires a hook  ──►  vibenotch-hook  ──► unix socket ──►  IPCServer
                     (CLI, bundled)      ~/.vibenotch/run   │
                                          /vibenotch.sock   ▼
  ◄── decision JSON ◄── blocks on ◄──── reply ◄──────  NotchPanel (SwiftUI)
      (allow/deny)      the socket                     Approve / Deny / Jump
```

1. On launch the app installs `vibenotch-hook` into each detected agent's config and starts an `IPCServer` on the socket.
2. When an agent needs permission, its hook fires `vibenotch-hook`, which opens the socket, sends a `request`, and **blocks** (Claude hooks are configured with a 24h timeout).
3. The app shows an approval card in the notch. Your tap is sent back over the socket; the hook translates it into the agent's decision JSON and exits 0.
4. If the app is down or the socket is gone, the hook returns "defer" / exits 0 — **the agent is never blocked by Vibe Notch.**

Full architecture and the reverse-engineered ground truth are in
[`docs/specs/2026-07-18-vibe-notch-v1-design.md`](docs/specs/2026-07-18-vibe-notch-v1-design.md).

## Build & run from source

**Requirements:** macOS 14+, Apple Silicon, Xcode 16 / Swift 6 toolchain
(`xcode-select --install` for the command-line tools is enough — no Xcode IDE required).

```bash
git clone <repo-url> vibe-notch && cd vibe-notch

# Assemble a signed VibeNotch.app from the SwiftPM products (no Xcode needed)
./scripts/bundle.sh            # debug build → .build/VibeNotch.app
open .build/VibeNotch.app
```

The app has no Dock icon (`LSUIElement`); look for the ✨ in the menu bar. It
auto-connects detected agents on first launch.

### Everyday development

```bash
swift build                    # compile all targets
swift test                     # run the test suite
swift build -c release         # optimized build
./scripts/bundle.sh release    # release .app
```

### Test the notch without a real agent session

`scripts/simulate.sh` feeds canned hook JSON straight through the real
hook → socket → notch path. Permission events **block until you click**, exactly
like a live session:

```bash
./scripts/bundle.sh            # build once so the hook binary exists
open .build/VibeNotch.app      # run the app
./scripts/simulate.sh bash     # a Bash approval card appears in the notch
./scripts/simulate.sh edit     # an Edit approval
./scripts/simulate.sh notify   # a "waiting" notification
./scripts/simulate.sh codex    # a Codex turn-complete card
```

### Opening in Xcode (optional)

Vibe Notch is a Swift Package, so there's no `.xcodeproj`. To use the IDE:

```bash
xed .            # or: open Package.swift
```

Xcode resolves the package and gives you schemes for each target, SwiftUI Previews
for the view files, and `⌘U` to run tests. Note: the notch panel is an `NSPanel`
positioned against real notch geometry, so **run the app (`⌘R` / `bundle.sh`) to
see the actual notch behavior** — Previews are best for iterating on individual
cards and components.

## Project structure

```
Sources/
  VibeNotchCore/        # no-UI engine — shared by the app and the hook
    AgentSpec.swift         registry: one spec per supported agent
    AgentHookInstaller.swift install/reconcile/remove hook entries (with backups)
    StatusLineInstaller.swift Claude status-line tee for usage data
    IPCProtocol.swift       line-delimited JSON messages (VNInbound / decisions)
    IPCServer.swift         socket server inside the app
    IPCClient.swift         socket client used by the hook
    UnixSocket.swift        thin POSIX socket wrapper
    UsageLoader.swift       parse Claude/Codex rate-limit files
    Paths.swift             ~/.vibenotch/{bin,run,cache,data} layout
  VibeNotch/            # the SwiftUI menu-bar / notch app
    main.swift              entry point
    AppDelegate.swift       status item, agent auto-connect, IPC wiring
    NotchPanelController.swift  the non-activating NSPanel under the notch
    NotchView.swift         root expanded/compact layout
    ApprovalCard.swift      permission card + Approve/Deny/Ask
    ActivityViews.swift     per-session activity + status
    Components.swift        pills, agent icons, spinners, helpers
    EventStore.swift        observable state: sessions + pending approvals
    UsageModel.swift        usage chips model
    TerminalJumper.swift    focus the source terminal (AppleScript)
    SoundManager.swift · VNColors.swift · VoxFlow.swift
  vibenotch-hook/       # the CLI binary wired into agent configs (fail-open)
    main.swift              parse each agent's payload → VNInbound → socket
Tests/VibeNotchCoreTests/   # installer round-trips, decision translation, IPC
Resources/Info.plist        # LSUIElement, bundle id, fonts
scripts/bundle.sh · simulate.sh
docs/specs · docs/plans
```

## Adding an agent

The `AgentSpec` registry is the extension seam. Most agents fall into an existing
family, so adding one is small:

1. **Claude-schema agents** (same hook JSON + `settings.json` shape, different home
   dir): add an `AgentSpec` pointing at the config dir — the generic installer and
   the Claude parse branch in `vibenotch-hook` handle the rest.
2. **New hook format** (like Gemini or Cursor): add the spec, its installer format,
   and a `--source <agent>` parse branch in `Sources/vibenotch-hook/main.swift` that
   maps the agent's events/fields onto `VNInbound`.
3. Add an installer round-trip test in `Tests/VibeNotchCoreTests`.

Keep the golden rule: **fail-open**. A hook must never block or crash the agent — on
any error it exits 0 (or returns "defer" for Claude permission requests).

## Uninstall

From the menu bar, toggle each agent off (restores its backed-up config), then quit.
Runtime files live in `~/.vibenotch/` and can be removed once the app is quit.

## Roadmap

- **P2:** Codex full approve/deny, Markdown plan preview (`ExitPlanMode`), sound polish.
- **P3:** more agents (Copilot, Kimi, Zai…), richer usage/quota.
- **P4:** SSH remote monitoring, external-display floating bar, tmux/split-pane precise jump, Ghostty window/tab targeting.

Details in [`docs/plans/`](docs/plans/).

## Contributing

Contributions welcome — this is meant to be a top-notch, community-built tool.

- Discuss non-trivial changes in an issue first.
- One focused change per PR; keep `swift build` and `swift test` green.
- Match the surrounding style: small files, `VN`-prefixed shared types, clear doc
  comments, fail-open error handling. Mark deliberate shortcuts with a `ponytail:`
  comment naming the ceiling.
- UI changes: attach a before/after screenshot or gif.

<!-- TODO: add CONTRIBUTING.md, LICENSE (GPL-3.0), and .swiftformat -->

## License

GPL-3.0 (planned — reference implementations studied for mechanisms are GPL).
A `LICENSE` file will be added before the tagged release.

## Acknowledgments

- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) (MIT) — notch window, hover-expand, morph physics.
- Vibe Island, `open-vibe-island`, and `boring.notch` — studied for hook/IPC/jump mechanisms.
