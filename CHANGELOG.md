# Changelog

## 0.4.0-beta.1 — unsigned beta

- Merge upstream commit `6f37bd5`: deliver asynchronous Codex answers to the exact thread, retain failed answers, and avoid double-submitting terminal choices.
- Preserve remaining question items across reply turns while expiring stale prompts on new work.
- Bound terminal and reply-helper execution without synchronous process waits; keep private answer data in stdin.

- Adapt notch placement and content to display safe areas, including the 15-inch MacBook Air layout.
- Keep Classic and add Focus, Aurora, and Studio interface styles, with a sample gallery export.
- Distinguish working, waiting, finished, interrupted, failed, and inactive sessions.
- Add a bounded local session timeline with hook/transcript provenance and approval lifecycle events.
- Read Codex activity from local transcripts and clear questions superseded by later user turns or interruptions.
- Review integration configuration changes before applying them; preserve unrelated hooks, make backups, and detect broken connections.
- Make Claude usage bridge installation explicit and restore the complete original status line when disconnected.
- Disable the optional dashboard by default, make it read-only, and require a launch key and same-origin access.
- Make automatic safe-list approvals opt-in for new installs and reject background shell operators and escaped command continuations.
- Restrict local socket/data permissions and handle broken pipe and invalid socket paths safely.
- Preserve other applications’ hooks during uninstall, including mixed groups and Codex hooks.
- Vendor the pinned DynamicNotchKit runtime sources for reproducible builds and bundle complete dependency/font licenses.
- Add bundle verification, isolated native hook smoke tests, checksummed artifacts, and a signing/notarization gate for public releases.

Direct DMG distribution is explicitly unsigned (ad-hoc signed, not notarized); macOS may block first launch. Matching source and SHA-256 checksums accompany the beta. Developer ID signing and remaining manual acceptance checks are tracked in `docs/release-readiness.md`.
