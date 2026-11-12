# Preparing a public beta

The release script distinguishes local validation, an explicitly unsigned public beta, and a signed public candidate. Neither command publishes a release. The GitHub workflow creates a draft only.

## Local validation

```bash
./scripts/check.sh
./scripts/bundle.sh release
python3 scripts/verify-bundle.py .build/VibeNotch.app
python3 scripts/smoke-hook.py .build/VibeNotch.app/Contents/Helpers/vibenotch-hook
./scripts/release.sh --preview --version 0.4.0-beta.1
```

`check.sh` requires full Xcode with XCTest. A Command Line Tools build or standalone assertion harness does not substitute for that suite. Use `xcode-select` to select a full Xcode installation on the release machine.

`--preview` creates an ad-hoc signed `LOCAL-PREVIEW.dmg`, a manifest recording incomplete public checks, and SHA-256 checksums under `dist/`. The disk image includes a local-preview notice. Do not promote it to the public download or tell users to disable Gatekeeper.

`VIBENOTCH_BUILD_DIR=.build/fresh-candidate` selects a fresh SwiftPM scratch directory. Runtime dependencies are vendored; provenance and local changes are in `Vendor/DynamicNotchKit/UPSTREAM.md`.

## Explicit unsigned beta

The maintainer chose direct unsigned beta distribution on 2026-11-12 while Apple Developer enrollment is pending. This mode does not claim Developer ID signing, notarization, or passing Gatekeeper assessment. macOS may block first launch. The website and disk image must disclose this before installation; never instruct users to disable Gatekeeper globally.

After reviewing and committing all source and tagging the exact candidate, run:

```bash
./scripts/release.sh --unsigned-beta --version 0.4.0-beta.1
```

This still requires clean tagged source, the full XCTest gate, bundle verification and hook smoke tests. Artifacts use the `UNSIGNED-BETA` suffix and include matching source, checksums, a factual manifest, and an installation notice. Only beta versions are allowed. Manual acceptance checks below remain unverified where not recorded; label the release as beta rather than claiming these passed.

## Public candidate

1. Review all source changes, version numbers, notices, screenshots, and the checklist below. Run the full CI suite with a supported Xcode.
2. Commit the reviewed source and create the intended `v0.4.0-beta.1` tag locally. The source tree must be clean. Tagging and pushing are deliberate release actions; do not infer authorization from local packaging work.
3. On the signing machine, install the Developer ID Application certificate and configure a `notarytool` keychain profile. Keep credentials out of source control and logs.
4. Run:

   ```bash
   NOTARY_PROFILE=vibenotch SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' ./scripts/release.sh --version 0.4.0-beta.1
   ```

The public path requires matching metadata and tag, a clean checkout, full checks, bundle verification, native hook smoke tests, Developer ID signing with hardened runtime, accepted app notarization, stapling, Gatekeeper assessment, and accepted disk-image notarization. It stops on failure; it never silently produces an unsigned public fallback.

Artifacts include the signed/stapled DMG, exact tagged source archive including vendored sources, notarization reports, a manifest, and checksums. A successful script proves its automated gates; it does not prove the manual user experience checks.

The current distribution is arm64 with minimum macOS 14.0. Version metadata is in `Resources/Info.plist` and `VNProtocol.build`; update both together. A stable release also needs `VNReleaseChannel` changed from `beta` and fresh release notes. Bundle build numbers default to the Git commit count; CI can set `BUILD_NUMBER` explicitly (1–9999).

## GitHub draft workflow

The `release` environment needs:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | Base64-encoded Developer ID Application certificate and private key export |
| `DEVELOPER_ID_P12_PASSWORD` | Export password |
| `APPLE_ID` | Notarization account |
| `APPLE_TEAM_ID` | Developer team identifier |
| `APPLE_APP_PASSWORD` | App-specific notarization password |

Configure environment protection and required CI checks in repository settings. The workflow imports signing material into a temporary keychain, runs the same release gate, prepares a **draft prerelease** for beta tags, and removes temporary signing material. It has not been exercised from this local workspace.

After inspecting the signed draft and testing the exact downloaded artifact on another Mac, a maintainer can authorize publication. Keep the source archive and license notices alongside binary downloads.

## Manual acceptance before publication

- Download the exact candidate on a fresh user account or second Mac. Open the DMG, drag to Applications, launch through Finder, verify Gatekeeper and onboarding, then quit/relaunch.
- Confirm no agent configuration changes occur before consent. Connect and disconnect each advertised adapter; test coexistence with foreign hooks, malformed settings, and backed-up configurations. Verify hook binary refresh after an update.
- Use real, supported versions of Claude and Codex: allow, deny, terminal-side answer/cancel, multiple questions, free text, interrupted sessions, and app quit while a request is pending. Confirm old questions disappear.
- Review notch alignment on the 15-inch Air, a 14-inch Pro, an external display, scaled modes, screen switching, sleep/wake, and menu-bar auto-hide. Include the minimum supported macOS in testing.
- Check all four styles, long commands/prompts, empty state, multiple sessions, keyboard focus, reduced motion, VoiceOver, and permission-denied flows for Calendar/Automation/Accessibility.
- Leave the app idle and with active agents for a sustained session. Check CPU, memory, transcript growth, timeline bounds, and media polling. Capture measured results rather than promising a resource budget.
- Confirm the optional dashboard is off by default and remains read-only. Verify phone notifications/SSH are opt-in. Inspect recordings and screenshots for private content.
- Test the fixture uninstall suite, then uninstall on a test account and verify unrelated hooks and original status lines survive.

## Launch copy draft

Vibe Notch brings your coding agents into your Mac’s notch. See what’s running, review supported permission requests, and catch questions without losing your place. The public beta adds four interface styles, a local activity timeline, and reviewed integration setup. Built with Swift for Apple Silicon, with source available under GPL-3.0.

Use current, sanitized screenshots and describe agent support and beta limitations accurately. No posting, tagging, pushing, or public release is part of local candidate preparation.
