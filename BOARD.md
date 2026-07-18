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
