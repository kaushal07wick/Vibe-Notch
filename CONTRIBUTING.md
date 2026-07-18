# Contributing to Vibe Notch

## Build & test

```bash
git clone https://github.com/kaushal07wick/Vibe-Notch.git
cd Vibe-Notch
./scripts/bundle.sh debug     # builds .build/VibeNotch.app (no Xcode project needed)
swift test                    # must stay green — CI enforces it
open .build/VibeNotch.app
```

Requirements: macOS 14+, Swift 6 toolchain (Xcode or Command Line Tools).

## Architecture in one breath

```
agent hook (settings.json / hooks.json / plugin)
  → vibenotch-hook (per-event CLI, fail-open)
  → unix socket ~/.vibenotch/run/vibenotch.sock (line-delimited JSON)
  → VibeNotch.app (EventStore → SwiftUI notch panel via DynamicNotchKit)
```

- `Sources/VibeNotchCore` — protocol, IPC, agent installers, terminal support,
  usage, policies. Pure logic; everything here is unit-testable.
- `Sources/vibenotch-hook` — the binary agents invoke. Must NEVER block or
  break an agent: no reply means "defer to the agent's own flow".
- `Sources/VibeNotchCLI` — `vibenotch list|approve|deny|send|interrupt`.
- `Sources/VibeNotch` — the app: notch UI, menu, dashboard, SSH tunnels.

## Ground rules

- `swift test` green before every push; CI runs it on every PR.
- The hook is **fail-open** — any change that can make an agent hang is a bug.
- Config edits (agent settings, TOMLs) must be idempotent, backed up once
  (`*.vibenotch.bak`), and remove only our own entries on uninstall.
- Protocol fields are append-only; never repurpose one (`docs/` + the
  compatibility note in `IPCProtocol.swift`).

## Adding support for a coding agent

See `docs/adding-an-agent.md` — most agents are a ~10-line registry entry.
