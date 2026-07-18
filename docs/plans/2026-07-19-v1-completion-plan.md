# Vibe Notch — v1 Completion Plan

> Execution: inline, one task per commit, screenshot-verified where UI changes.
> Reference mechanisms come from the scanned repos (`open-vibe-island`, `boring.notch`,
> live Vibe Island) — documented in `docs/specs/`. We implement our own clean code
> against those mechanisms; project license is GPL-3.0 (reference apps are GPL).

**Goal:** Close the gap to Vibe Island's feature list with a clean, modular,
reliable codebase, then ship a README + DMG.

**Architecture:** SwiftPM, 3 targets — `VibeNotchCore` (protocol, IPC, installers,
usage), `vibenotch-hook` (agent-side client), `VibeNotch` (app/UI). UI split into
focused files. Every agent = one `AgentSpec` + installer conformer.

---

## Task 0 — Codebase cleanup (modular, no dead code)

- Delete dead symbols: `AsciiCreature`, `PixelCaret`, any unused color/font tokens.
- Split `NotchView.swift` (~550 lines) into:
  - `NotchView.swift` — root `ExpandedContent` + compact flanks only
  - `ApprovalCard.swift` — permission card + WideButton
  - `ActivityViews.swift` — ActivityCard, SessionRow, TerminalBlock, status helpers
  - `Components.swift` — pills, AgentIcon, PixelInvader, AsciiSpinner, age/one-line helpers
- Keep naming consistent (`VN` prefix for shared types).
- `swift build` + `swift test` green. Commit.

## Task 1 — Every agent: registry + installers (2 → ~10+)

Mechanisms (from open-vibe-island scan):
- **Claude-schema family** — same hook JSON schema + settings.json format, different
  home dir: Claude (`~/.claude`), Qwen (`~/.qwen`), Qoder (`~/.qoder`),
  Droid/Factory (`~/.factory`), CodeBuddy (`~/.codebuddy`). One generic
  `ClaudeSchemaInstaller(dir:sourceID:)` covers all.
- **Gemini CLI** — `~/.gemini/settings.json`, hooks object; events
  `SessionStart/SessionEnd/BeforeAgent/AfterAgent/Notification`; payload has
  `cwd`, `session_id`, `prompt`, `message`. `--source gemini` parse branch.
- **Cursor** — `~/.cursor/hooks.json`, `hooks[event] = [{command}]`; events
  `beforeSubmitPrompt/beforeShellExecution/afterFileEdit/stop`; payload
  `conversation_id`, `workspace_roots`, `command`. `--source cursor` branch.
- **Codex** — done (notify TOML).
- Detection: an agent is "available" iff its config dir exists. **Zero-config**:
  on first launch, auto-connect every detected agent (menu shows per-agent toggle).
- Hook: per-source parse → same `VNInbound`. Fail-open everywhere.
- Tests: installer round-trip per format (JSON family, Gemini, Cursor).

## Task 2 — Usage tracking (Claude + Codex)

- **Claude**: install a status-line command into `~/.claude/settings.json` that tees
  `.rate_limits` → `~/.vibenotch/cache/rl-claude.json` (wrap any existing status
  line; backup first). Loader reads `five_hour`/`seven_day`:
  `used_percentage`, `resets_at` (epoch or ISO8601).
- **Codex**: newest `~/.codex/sessions/**/rollout-*.jsonl`, last
  `event_msg`/`token_count` line → `rate_limits.primary/secondary`
  (`used_percent`, `window_minutes`, `resets_at`).
- Refresh: file-watch + 60s timer.
- UI: header chips in expanded panel — `Claude 5h 26%` (peak window), color
  ≥90 red / ≥70 orange / else green; tooltip lists all windows + reset countdown.

## Task 3 — Precise terminal jump

- Hook captures the session TTY (`ps -o tty= -p <ppid chain>`), sent in `VNInbound`.
- iTerm2 + Terminal.app: AppleScript walk windows/tabs/sessions, match tty → select
  exact tab. Ghostty/others: app activate (no scripting API).
- `ponytail:` split-pane/tmux precision deferred; app+tab covers the 90% case.

## Task 4 — Plan review (Markdown)

- `ExitPlanMode` PermissionRequest carries `tool_input.plan` (Markdown).
- ApprovalCard: when tool == ExitPlanMode → scrollable Markdown block
  (`AttributedString(markdown:)`, no new dependency), buttons
  "Approve plan" / "Keep planning".

## Task 5 — Sound polish

- Keep synthesized bells; add per-event enable + volume in menu.
- `ponytail:` custom sound packs deferred (folder `~/.vibenotch/sounds` scan later).

## Task 6 — Package & ship

- App icon: render the pixel invader → iconset → `.icns` (script, PIL + iconutil).
- `LICENSE` (GPL-3.0) + acknowledgments (DynamicNotchKit MIT, Departure Mono,
  open-vibe-island/boring.notch references).
- `README.md`: what/why, screenshots, agent table, install (DMG + build-from-source),
  how hooks work, uninstall.
- `scripts/release.sh`: `swift build -c release` → bundle → codesign (Developer ID
  if present, else ad-hoc) → `hdiutil` DMG at `dist/VibeNotch-<version>.dmg`.
- Version 0.2.0. All tests green.

## Out of v1 (explicit)

- SSH remote (own subsystem), Codex GUI approval (app-server protocol),
  VoxFlow (waiting on source), remaining ~14 niche agents (spec'd via the same
  registry — add as conformers when configs are known).
