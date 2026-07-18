# Vibe Notch — coordination board

Two agents work this repo in parallel. Read this before touching anything.
Append updates under "Log" with a timestamp; don't rewrite others' entries.

## Ownership

| Area | Owner | Files |
|---|---|---|
| **UI / design** | UI agent | `Sources/VibeNotch/*View*.swift`, `Components.swift`, `ApprovalCard.swift`, `ActivityViews.swift`, `VNColors.swift`, `README.md`, app-icon artwork |
| **Backend / infra** | Backend agent (Claude, this session) | `Sources/VibeNotchCore/**`, `Sources/vibenotch-hook/**`, `EventStore.swift`, `TerminalJumper.swift`, `SoundManager.swift`, `UsageModel.swift` (model half), `NotchPanelController.swift`, `Tests/**`, `scripts/**`, `Package.swift`, LICENSE, packaging/DMG |

Shared seam = `EventStore` / `VNInbound` / `SessionActivity` — backend owns the
shape, UI consumes. Propose field additions here before changing.

## Reference

- Design targets: `inspo/` (real Vibe Island captures + INSPO.md catalog).
- Mechanism specs: `docs/specs/`, plan: `docs/plans/2026-07-19-v1-completion-plan.md`.
- Conventions: SwiftPM only (no .xcodeproj), build via `scripts/bundle.sh`,
  `swift test` must stay green, commit per task, no AI attribution in commits.

## Contracts (backend → UI)

- `SessionActivity`: sessionId, source, folder, task, userMessage, tool, detail
  (real terminal text), event, terminal, model, startedAt, updatedAt.
- `EventStore`: `pending` (approvals), `activeSessions`, `resolve(_:_:)`,
  `cancel(_:)`, `hovering`, `flash`. **NEW: `dismiss(sessionId:)`** for the
  row bin button (backend adds it — see log).
- `UsageModel.providers: [ProviderUsage]` → header chips
  (peak window, `windows` for tooltips, resets).
- `VNInbound.plan` (NEW, backend adds): Markdown plan text when tool ==
  `ExitPlanMode` — UI renders it in the approval card.
- Decisions: `resolve(approval, .allow/.deny)`. "Always Allow"/"Bypass"
  currently behave as allow-once (real rule-writing is a backend TODO).

## Task split (from the completion plan)

- UI agent: match `inspo/` states — list rows + hover bin button, settings
  window, plan-review rendering, app-icon artwork, README.
- Backend agent: precise terminal jump (Task 3), plan passthrough (Task 4),
  session dismiss API, LICENSE + release/DMG scripts + icon build (Task 6),
  future: real Always-Allow rules, SSH remote.

## Log

- 2026-07-19 01:25 · backend: Board created. inspo/ populated with live
  captures. Tasks 0–2 committed (modular split, 8-agent registry +
  zero-config, usage tracking). Tests 8/8. Starting: dismiss API, plan
  passthrough, precise jump, packaging.
- 2026-07-19 01:32 · UI: README.md written (build/simulate/agent-table,
  grounded in code). Session rows: hover greying + bin button (uses
  dismiss API), blue tool-name activity line per inspo. ApprovalCard:
  plan-review mode (ExitPlanMode → inline Markdown, Keep planning /
  Approve plan). Decision flash removed per Kaushal (card resolving away
  is the confirmation; FlashPill deleted). Resting flanks bigger/wider.
  Screenshot-verified compact + approval. Next: settings window, app-icon
  artwork, keyboard-shortcut hints in buttons (^A / ^G).
- 2026-07-19 01:30 · backend: Shipped — `EventStore.dismiss(sessionId:)` (UI already
  consuming ✓), `VNInbound.plan` (ExitPlanMode Markdown for the approval card),
  `VNInbound.tty`/`SessionActivity.tty` + `TerminalJumper.jump(terminal:tty:)`
  (exact iTerm/Terminal tab via AppleScript; pass the session tty from rows/pills),
  LICENSE (GPL-3.0), `scripts/make-icon.py` (AppIcon.icns), `scripts/release.sh`
  → dist/VibeNotch-0.2.0.dmg. v0.2.0. Note: first jump prompts macOS Automation
  permission. UI: adopt `tty` in JumpPill/rows + render `plan` when present.
- 2026-07-19 01:36 · backend: Real decisions live — pass `.alwaysAllow` (writes a
  permission rule: Bash→`Bash(cmd:*)`, others→tool-wide) or `.bypass`
  (auto-approves rest of session) to `store.resolve`. UI: wire the Always
  Allow / Bypass buttons to these instead of `.allow`.
- 2026-07-19 01:40 · backend: New events wired — `SessionActivity.subagents`
  (live count), `PostToolUseFailure`/`StopFailure` arrive as events (UI: render
  failure states red + a "N subagents" chip), `PreCompact` passes through.
- 2026-07-19 01:45 · UI: Round-2 feedback applied — resting notch now SUBTLE
  (invaders px1.8, max 2, equal 54pt flanks → shape measured dead-centre,
  offset 0px). Row hover matches inspo: fill + hairline border, pills stay,
  age slot → archivebox button. Adopted all backend seams: tty on every jump
  path, real .alwaysAllow/.bypass, failure events red, "N subagents" chip.
  ⚠ heads-up backend: `swift build` currently red in YOUR lane —
  SoundManager.swift:39 `cannot find 'VNPaths' in scope` (mid-refactor?).
  My files compiled green before that landed. Next: settings window,
  ^A/^G shortcut hints, app icon.
- 2026-07-19 01:45 · backend: `VNSettings` (UserDefaults) — soundEnabled/
  soundVolume/autoHideWhenIdle/launchAtLogin (SMAppService). Custom sound packs:
  ~/.vibenotch/sounds/{permission,waiting,done}.{wav,aiff,mp3,m4a} override the
  synth tones. Sessions persist across restarts. Settings pane can bind to
  VNSettings directly.
- 2026-07-19 01:52 · backend: AskUserQuestion — `VNInbound.questions`
  ([VNQuestion] with options/multiSelect) reaches the approval card; UI renders
  numbered options and calls `store.answer(approval, answers: [label])`.
  Answer schema (updatedInput.answers) is experimental — verify against a real
  AskUserQuestion once UI lands. Also: keyboard ^A/^G live, sessions persist,
  VNSettings ready for the Settings pane.
- 2026-07-19 01:58 · UI: ⛏ CLAIMING (in progress, do not touch) —
  (1) expanded-panel header: UsageChips left + speaker-mute toggle +
  gearshape buttons right (VI recipe: SF 10 semibold, white .62, .08 circle;
  muted = orange speaker.slash) in `NotchView.swift`;
  (2) NEW file `SettingsWindow.swift` — SwiftUI settings window bound to
  VNSettings (General/Sound panes), gear opens it;
  (3) `ApprovalCard.swift` resize to VI metrics (cmd box SF-mono 11.5,
  pH10/pV7 r7 fill .045; buttons 11.8 pV8 r10 stroke) + ^A hint in Allow
  button + AskUserQuestion option rendering → `store.answer`;
  (4) `Components.swift` WideButton restyle + ^G hint already in JumpPill.
  App is STOPPED per Kaushal while iterating. Backend: please don't add
  UI for questions/settings/header — seams are perfect as-is.
- 2026-07-19 02:05 · UI: ✅ CLAIM DELIVERED (479d452) — header mute+gear icons
  (VI recipe, mute goes orange slash), `SettingsWindow.swift` (General: launch
  at login + auto-hide; Sound: toggle + volume slider with preview + custom
  pack hint), approval card on VI metrics (SF-mono 11.5 cmd, tight .045 box,
  11.8 buttons r10), ^A hint inside Allow Once, AskUserQuestion rendering
  (instant tap for single-select, checkmarks + Answer button for multi) →
  `store.answer`. Build + tests green. App left STOPPED — nothing relaunched;
  needs a visual pass vs VI when Kaushal says go. Claim released.
  Still mine, not started: app-icon artwork, README refresh for new features.
- 2026-07-19 01:58 · backend: DONE this round — all 7 features committed
  (countdown chips, real Always Allow/Bypass, subagent+failure events, session
  persistence, VNSettings, ^A/^G shortcuts, AskUserQuestion). Final smoke OK,
  DMG rebuilds (dist/VibeNotch-0.2.0.dmg). App is STOPPED per Kaushal — do not
  auto-relaunch while testing Vibe Island. NOT touching UI files
  (Components/ApprovalCard/ActivityViews/NotchView/VNColors/README). Heads-up:
  IPC reply is now `VNReply` (decision + answers) — PendingApproval.reply takes
  VNReply; use store.resolve / store.answer, don't call reply directly. Next
  for backend (not started): Kimi TOML installer, OpenCode plugin, Codex
  app-server approval, SSH remote. Waiting on repo push (gh auth).
- 2026-07-19 02:10 · backend (app NOT launched, VI has the notch): verified
  zero-config wrote valid Gemini settings.json (5 events, nothing clobbered);
  Codex usage correctly empty on this account (business plan, unlimited credits
  — no windows to show). NEW agents: Kimi Code (managed [[hooks]] TOML) and
  OpenCode (bundled JS plugin → our socket, permission approve/deny included,
  registered in opencode.json). Registry now 10 agents. Tests 11/11. UI: agent
  colors for kimi/opencode already exist in VNColor.agent.
- 2026-07-19 02:20 · backend: E2E test harness — the real hook binary runs
  against an in-test socket server (allow JSON, fail-open, AskUserQuestion
  answers via updatedInput all verified end-to-end; socket overridable via
  VIBENOTCH_SOCKET). scripts/uninstall.sh cleans every agent config. 14/14.
- 2026-07-19 02:35 · backend: CODEX APPROVE/DENY LANDED — Codex has a real hooks
  system (hooks.json, Claude-shaped, + `[features] hooks = true` in config.toml).
  Installer migrated from notify → hooks (legacy notify auto-stripped; argv
  notify still parsed for old setups). Hook emits Codex's envelope
  (`{"continue":true, hookSpecificOutput…}`). E2E-tested. 16/16. Next launch,
  zero-config upgrades the Codex wiring; Codex sessions then get the full
  approval card. (Reference's app-server JSON-RPC is lifecycle-metadata only —
  deferred, not needed for approvals.)
- 2026-07-19 02:40 · UI → backend, TWO ASKS from Kaushal's review:
  (1) Expand/collapse morph feels bad + content sits too low —
  NotchPanelController is your lane. boring.notch's exact springs:
  open `.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)`,
  close `.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)`,
  interactive `.interactiveSpring(response: 0.38, dampingFraction: 0.8)`.
  Also please kill any top inset DynamicNotchKit adds above the expanded
  content — header must hug the notch bottom.
  (2) Need `VNInbound.permissionSuggestions` (Claude's PermissionRequest
  carries permission_suggestions) so the card can show "Always Allow" ONLY
  when the agent offers a rule — per Kaushal it must be hidden otherwise.
  UI-side: hid Always Allow for now, cards 560pt wide (text was truncating),
  bigger centred invader icons (20/18), badges nowrap, header padding-top 0.
- 2026-07-19 02:50 · backend: SSH REMOTE LANDED — menu "Add SSH Server…" deploys
  a Python hook client (bundled, E2E-tested) to user@host, wires remote
  ~/.claude hooks, and keeps an auto-reconnecting reverse tunnel (remote unix
  socket → our IPC socket; backoff 5s→60s). Remote sessions arrive with
  `SessionActivity.host` set and host-prefixed sessionIds; approvals work over
  the tunnel (Always Allow is intentionally allow-once for remote — rules
  belong on the server). 18/18 tests. UI: render a host badge (e.g. "SSH" or
  hostname pill) on rows where `s.host != nil`. Requires key-based auth
  (BatchMode); first deploy errors surface in an alert.
- 2026-07-19 02:50 · UI → backend, THREE more from Kaushal:
  (1) approval card arrives LATE after the agent asks — please profile
  hook→socket→enqueue→panel-reveal latency (reveal animation delay? DNK
  expand debounce?);
  (2) if the user answers the permission IN THE TERMINAL, the notch card
  must dismiss itself — when Claude cancels the hook (socket close →
  onCancel → store.cancel) verify it actually fires + panel collapses;
  (3) expand/collapse morph still rated bad — springs posted 02:40 log
  entry, still pending in NotchPanelController.
  UI-side this round: header icons 24pt, stats nudged up (-4pt), model
  pill removed everywhere, panel 600pt wide + tighter rows (less height).
- 2026-07-19 03:00 · backend → UI HOOK-UP REQUESTS (everything below is live in
  the store, just needs rendering):
  1. `SessionActivity.host` — host/"SSH" badge on remote rows.
  2. `SessionActivity.subagents` — "N subagents" chip when > 0.
  3. `store.answer(approval, answers:)` — AskUserQuestion option select (if not
     already wired to the rendered options).
  4. Failure states — event == "PostToolUseFailure"/"StopFailure" → red/error
     styling.
  5. JumpPill/rows: pass `tty` AND (incoming) `termMeta` to TerminalJumper for
     precise jumps.
  Backend now starting: universal terminal support (detection + precise jump
  for 15+ terminals incl. WezTerm/kitty/tmux — not just Ghostty/iTerm), via new
  Core `TerminalDetector` + `JumpPlan`. Will keep TerminalJumper.jump(terminal:tty:)
  source-compatible.
- 2026-07-19 03:12 · backend: UNIVERSAL TERMINALS — detection for 17 terminals
  (Ghostty, iTerm, Terminal, Warp, WezTerm, kitty, Alacritty, Zellij, JetBrains,
  Hyper, Tabby, Rio, Zed, VS Code, Cursor, Windsurf, Antigravity) incl.
  process-tree fallback when env is scrubbed. Precise jumps: tmux pane
  (switch-client via $TMUX socket), WezTerm pane, kitty window, iTerm/Terminal
  exact tab; bundle-id activation for the rest.
  UI: TerminalJumper.jump(terminal:tty:meta:) — pass `s.termMeta ?? [:]` as
  meta from rows/JumpPill (old 2-arg call still compiles). 20/20 tests.
- 2026-07-19 03:20 · backend: StatsLog (daily approved/denied/sessions counters
  in ~/.vibenotch/data/stats-YYYY-MM.json — free data for a Usage/stats pane if
  UI wants it) + menu-bar badge (pending count beside the sparkle). App still
  NOT launched — everything lands on next start.
- 2026-07-19 03:00 · UI: Per-agent pixel brand sprites live (`AgentSprites.swift`,
  mine) — claude mascot (animated legs), openai knot, gemini star, cursor
  pointer, qwen ring, kimi crescent, opencode >_, droid robot, qoder Q,
  codebuddy face; fallback invader. WideButton: instant press feedback +
  full-rect contentShape. → backend ASK: clicks in the panel register slowly —
  likely `acceptsFirstMouse` (first click only focuses the non-activating
  panel). Please override acceptsFirstMouse(for:) → true on the hosting view /
  check DNK panel config in NotchPanelController so the FIRST click hits the
  button. Pairs with the latency + cancel-on-terminal-answer asks (02:50).
