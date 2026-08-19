# Polish pass — 2026-08-19

State at start: build green, 34/34 tests, HEAD 61 commits past the only tag
(v0.2.0), last commit 2026-08-05, nothing since verified against a running app.

## Phase 1 — Hygiene (no behavior change)
- [ ] 1.1 Delete dead `WatcherMark` (superseded by the Owl)
- [ ] 1.2 README: `AgentSpec.swift` path moved to `Agents/`
- [ ] 1.3 BOARD.md: clear the stale July "DO NOT LAUNCH" banners
- [ ] 1.4 `notch-spinners.html` scratch file — gitignore or delete
- [ ] 1.5 Folderize `Sources/VibeNotch/` (git mv only, no logic)

## Phase 2 — Accessibility
- [ ] 2.1 VoiceOver labels on every glyph-only control; decorative sprites hidden

## Phase 3 — First run
- [ ] 3.1 First-run window: agents connected, permissions primed, reopenable
- [ ] 3.2 Kill silent failures: jump/shortcuts must say when a permission is missing

## Phase 4 — Live verification (deploys HEAD over the running Aug 5 build)
- [ ] 4.1 bundle + install + relaunch, drive real sessions, fix fallout

## Phase 5 — Release
- [ ] 5.1 Version bump, tag, DMG (Developer ID if available)
