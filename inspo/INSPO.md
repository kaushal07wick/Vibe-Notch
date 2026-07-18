# Vibe Island reference catalog

Fresh captures from the live app (v1.0.42) + notes from Kaushal's screenshots.
UI work should match these pixel-for-pixel where sensible.

## Captured here

- `vi-compact.png` — closed pill: two blue pixel invaders left of notch, session
  count right. Nothing else.
- `vi-sessions-list.png` — expanded, 2 sessions. Stats header:
  `❋ 5h 35% 20m | 7d 21% 5d20h` left, speaker + gear icons right.
  Rows: colored invader mascot (per-agent, e.g. blue/green) · bold `folder · task`
  · `You: <last msg>` · activity line (`Read /path…` in blue tool-name style, or
  latest agent reply in grey). Pills right: `Claude` (clay tint) `Ghostty` `<1m`
  or a green live dot.
- `vi-permission-card.png` — approval: stats header on top, then optional banner
  card ("Codex updated — confirm authorization" + `Authorize` button + `×`),
  then `folder` title row with pills + `^G↗`, `⚠ Bash` line, boxed
  `$ command` + grey description, buttons `Deny / Allow Once / Bypass`
  (`Always Allow ^A` appears when applicable — carries its keyboard shortcut
  inside the button), footer `Show all 2 sessions`.

## From Kaushal's screenshots (not captured as files)

- **Row hover → trash/archive button**: hovering a session row highlights it
  (subtle lighter fill, rounded) and shows a **bin icon button** on the right
  edge → dismisses/archives that session from the list.
- **Settings window** (separate window, warm dark brown, sidebar + panes):
  - Sidebar: General / Integrations / Notifications / Display / Sound / Usage,
    Advanced: Shortcuts / SSH Remote / Labs, Vibe Island: Pass / About.
  - General pane: Launch at Login toggle; Expansion — "Expand notch on hover"
    toggle + "Hover duration" slider (0.15s) + "Smart suppression — don't
    auto-expand when the agent's terminal tab is in focus"; Visibility — "Hide
    in fullscreen", "Auto-hide when no active sessions"; Dismissal —
    "Auto-collapse on mouse leave", "Auto reveal dwell 5s (ESC to close
    sooner)", "Dismiss auto reveal on outside click".
- **Keyboard shortcuts** shown inline in buttons (`^A` Always Allow, `^G` jump).
- Stats header shows **time-remaining** next to each usage window
  (`5h 35% 20m` = 20 min until 5h window resets).
