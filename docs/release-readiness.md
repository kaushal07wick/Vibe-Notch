# 0.4.0-beta.1 readiness record

Local preparation on 2026-11-12. The maintainer subsequently authorized direct unsigned beta distribution on 2026-11-12. The initial signed-release checklist below is retained as a record; signing and notarization remain pending and are not claimed by the unsigned beta. Public website copy and the disk image disclose the macOS first-launch limitation. The explicit `--unsigned-beta` path retains clean source, tag, full tests, bundle verification, source archive, and checksum requirements.

## Implemented

- Display-aware notch layout and four interface styles; Classic remains the default.
- Codex activity/question lifecycle fixes, session phases, and bounded event timelines.
- Reviewed configuration plans with backups, connection health, and explicit Claude usage bridge consent.
- Private IPC socket and managed directories, invalid path checks, and broken-pipe handling.
- Optional dashboard off by default, read-only, restricted to loopback and a per-launch key.
- Automatic safe-list approvals off by default for new installs; existing explicit preferences remain respected. Prefix rules are a convenience, not a command sandbox.
- Uninstall preserves mixed foreign hooks and original status-line objects and validates configurations before modifying them.
- Vendored DynamicNotchKit sources with provenance; complete GPL, MIT, and SIL OFL notices in the app.
- A reproducible bundle script, automated checks, hook smoke tests, local preview DMG, artifact manifests/checksums, and a signed/notarized public release path.
- Updated README, changelog, privacy/data inventory, and release operator instructions.

## Verified locally

| Check | Result |
|---|---|
| Release build in a new scratch directory | Passed with installed macOS 26.5 SDK, without dependency downloads or checkout-cache edits; full Xcode build and final preview packaging also passed |
| Full production check script | Passed with Xcode 27.2: 78 XCTest tests, zero failures, plus five release fixture tests and four Codex bridge tests |
| Developer tools | Command Line Tools 27.2 and full Xcode 27.2 installed; Xcode selected, license/first-launch setup complete, notarytool/stapler available |
| Bundle structure, arm64 architecture, minimum deployment targets, resources, licenses, ad-hoc signature integrity | Passed |
| Uninstall fixture tests and preview metadata tests | Five tests passed |
| Bundled native hook over isolated Unix sockets | Five tests passed: allow/deny, Codex envelope, question answers, absent app, disconnected app |
| Dashboard authorization, status-line plan/restore, and native IPC privacy/path handling | Eight focused checks passed with standalone assertions; **not an XCTest suite result** |
| Existing pure core regressions (standalone assertions) | 23 passed, including shell matcher cases; not a full XCTest result |
| Disk image inspection | Checksums passed; read-only mounted app verified with licenses, preview notice, and Applications shortcut |
| Refreshed local app | Launched successfully; only Vibe Notch was running, Aria remained stopped |
| Public-release preflight on this working tree | Refuses uncommitted source instead of producing a public artifact |
| Local preview packaging | Earlier beta DMG verified; rebuild it after the Codex merge before sharing |

Local validation logs and generated artifacts are ignored build output; no real agent commands are executed by the hook smoke tests.

Installed the merged build at `/Applications/VibeNotch.app`, stopped the previous instance, and verified one running copy with a working read-only control connection. The user chose to keep the Vibe Notch name; no rename is pending. The local beta source checkpoint is retained in Git’s stash and under `.build/merge-backups/`.

## Required before publication

1. **Remote CI.** The full local `scripts/check.sh` now passes with Xcode 27.2 (78 XCTest tests, no failures). The new GitHub CI workflow still needs its first remote run on the reviewed commit. Earlier Command Line Tools-only XCTest failures were resolved by installing/configuring Xcode.
2. **Developer ID and notarization.** No Developer ID signing identity is installed locally. Configure signing credentials and notarization, then generate a signed candidate through the public release script. The current preview is ad-hoc signed and unnotarized.
3. **Reviewed source commit and matching tag.** This workspace contains uncommitted development work. Review and commit it, run CI, then authorize the beta tag and draft workflow.
4. **Manual acceptance of the exact candidate.** Fresh account/second Mac, minimum macOS, agent versions, permission/question cancellation, 15-inch Air and 14-inch Pro geometry, external/scaled displays, sleep/wake, reduced motion, accessibility, and sustained CPU/memory checks. See the full matrix in `releasing.md`. These checks are pending; do not infer them from compilation.
5. **Public presentation.** Capture current sanitized screenshots and a short demo, review beta wording and integration limitations, then approve the signed draft and download links. The Vibe Notch name is retained.

The production release path refuses a dirty/untagged tree, missing credentials, test failures, invalid bundles, failed hook smoke tests, or rejected notarization. It prepares a reviewable artifact, not proof that all manual checks are complete.
