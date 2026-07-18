# Adding a coding agent

Most agents take one registry entry + one test. The registry drives detection,
zero-config install, the menu, and uninstall.

## 1. Find the agent's hook mechanism

Four already-implemented mechanisms cover most tools:

| Mechanism | Works for | Config it edits |
|---|---|---|
| `.jsonHooks(events:)` | Claude Code schema + its forks (Qwen, Qoder, Droid, CodeBuddy) and Gemini CLI | `~/.<agent>/settings.json` |
| `.cursorHooks(events:)` | Cursor-style flat hooks | `~/.cursor/hooks.json` |
| `.codexHooks(events:)` | Codex (hooks.json + `[features] hooks = true`) | `~/.codex/` |
| `.kimiTOML(events:)` | TOML `[[hooks]]` blocks | `~/.kimi/config.toml` |
| `.opencodePlugin` | JS-plugin hosts | `~/.config/opencode/` |

## 2. Register it

In `Sources/VibeNotchCore/Agents/AgentSpec.swift`, add to `Agents.all`:

```swift
.init(id: "myagent", name: "My Agent", configDir: ".myagent",
      configFile: "settings.json", mechanism: .jsonHooks(events: claudeEvents)),
```

The `id` becomes the hook's `--source` flag. If the agent speaks the Claude
hook schema, you're done — the hook binary already parses it.

## 3. Brand it

`Sources/VibeNotch/VNColors.swift` → add a case to `VNColor.agent(_:)` with the
agent's hue. (Pixel sprite optional — `AgentSprites.swift`.)

## 4. Test it

Add a round-trip test in `Tests/VibeNotchCoreTests` asserting install is
idempotent and uninstall preserves foreign config (copy an existing one).

If the agent's payloads differ from every mechanism above, add a parse branch
in `Sources/vibenotch-hook/main.swift` mapping its events onto our canonical
names (`SessionStart/UserPromptSubmit/PreToolUse/PostToolUse/Stop/...`) — see
the `gemini` and `cursor` branches for the pattern.
