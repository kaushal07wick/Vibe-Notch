# Privacy and local data

Vibe Notch does not require an account and has no built-in analytics service. This describes the source for the 0.4.0 beta; it is not a claim that agent output is free of secrets.

## Data on your Mac

| Data | Purpose and location |
|---|---|
| Agent hook events | Show sessions, permissions, questions, commands, diffs, project paths, and prompt excerpts. Sent through `~/.vibenotch/run` using a local Unix socket. |
| Codex question replies | On an explicit answer, send the selected text through private stdin to a bundled helper, then to the exact thread over Codex’s user-owned local control socket. No reply text is placed in process arguments. |
| Agent transcripts | Read existing local Claude/Codex session information for activity, history, and supported questions. Source transcripts stay in the agent’s own storage. |
| Timeline | A local summary under `~/.vibenotch/data`; bounded to 1,000 entries overall, 200 per session, and seven days. Pruning occurs as the timeline is processed. This retention rule does not cover other caches, agent transcripts, backups, or system backups. |
| Configuration and backups | Integration edits affect the agent’s own configuration files after review. Backups remain beside those files; the usage bridge also saves the original status line. These can contain sensitive existing configuration. |
| Cache, statistics, and policies | Stored under `~/.vibenotch`; include usage snapshots and user approval preferences. No automatic seven-day deletion is promised for these files. |
| App preferences | macOS user defaults, including display style and optional feature settings. |
| File tray | Holds user-selected files for reuse; do not treat the tray as a secure vault. |
| Calendar and media | Read local event and now-playing information for optional widgets, subject to available macOS permissions. |

The app restricts its managed directories to the current user and its IPC socket to owner access. This does not protect information from another process running as you. Local commands, terminal automation, and the CLI can act on sessions; grant access to trusted software only.

## Optional network features

- **Phone notifications:** when configured, send notification content to `ntfy.sh` using the topic you choose. Topic secrecy and the notification service’s policies matter. This feature is off until configured.
- **SSH:** connects to remote Macs you select to receive their agent activity through a tunnel. Those machines and their SSH configuration are part of your trust boundary.
- **Web dashboard:** disabled by default. When enabled, listens on loopback and exposes a read-only view with a per-launch key. Treat its URL as sensitive; a browser displaying it can show agent content.
- **Links:** opening project or issue links launches your browser and contacts the destination.

The agent tools themselves may use cloud services independently of Vibe Notch.

## Removing data and reporting issues

Disconnect integrations before deleting the app. `scripts/uninstall.sh --dry-run` previews managed configuration cleanup; running it removes local Vibe Notch data unless `--keep-data` is used. Configuration backups, macOS preferences, agent-owned transcripts, tray source files, and system backups can remain and must be reviewed separately.

Redact credentials, prompts, paths, account names, and private code from reports. Do not attach complete agent settings or transcript files to a public issue. Screen-share suppression can reduce accidental exposure but is not a security boundary.
