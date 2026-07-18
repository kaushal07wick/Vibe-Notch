import Foundation

/// Everything vibe-notch knows about one coding agent: identity, where its
/// config lives, and which install mechanism wires our hook into it.
public struct AgentSpec: Sendable, Identifiable {
    public enum Mechanism: Sendable {
        /// Claude Code's settings.json hook schema (shared by its forks and Gemini CLI).
        case jsonHooks(events: [HookEvent])
        /// Cursor's `hooks.json` — flat `hooks[event] = [{command}]` map.
        case cursorHooks(events: [String])
        /// Codex's `hooks.json` (Claude-shaped) + `[features] hooks = true` flag.
        case codexHooks(events: [HookEvent])
        /// Kimi's `config.toml` `[[hooks]]` array-of-tables (Claude-schema payloads).
        case kimiTOML(events: [HookEvent])
        /// OpenCode's JS plugin, registered in opencode.json's `plugin` array.
        case opencodePlugin
    }

    public struct HookEvent: Sendable {
        public let name: String
        public let timeout: Int?
        public let matcher: String
        public init(_ name: String, timeout: Int? = nil, matcher: String = "*") {
            self.name = name
            self.timeout = timeout
            self.matcher = matcher
        }
    }

    public let id: String        // hook `--source` flag and UI identity
    public let name: String      // display name
    public let configDir: String // home-relative, e.g. ".claude"
    public let configFile: String
    public let mechanism: Mechanism

    public var configDirURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(configDir)
    }
    public var configFileURL: URL { configDirURL.appendingPathComponent(configFile) }

    /// An agent is available when its config directory exists.
    public var isDetected: Bool {
        FileManager.default.fileExists(atPath: configDirURL.path)
    }
}

public enum Agents {
    /// Claude Code's event set: blocking PermissionRequest + activity events.
    static let claudeEvents: [AgentSpec.HookEvent] = [
        .init("PermissionRequest", timeout: 86_400),
        .init("Notification"), .init("Stop"), .init("SessionStart"),
        .init("UserPromptSubmit"), .init("PreToolUse"), .init("PostToolUse"),
        .init("SessionEnd"),
        .init("SubagentStart"), .init("SubagentStop"),
        .init("PostToolUseFailure"), .init("StopFailure"), .init("PreCompact"),
    ]

    /// Codex's hook events. PermissionRequest is the blocking approval channel;
    /// Pre/PostToolUse exist but echo noisily into the terminal, so we skip them.
    static let codexEvents: [AgentSpec.HookEvent] = [
        .init("SessionStart", matcher: "startup|resume"),
        .init("UserPromptSubmit"),
        .init("PermissionRequest", timeout: 3600),
        .init("Stop"),
    ]

    /// Gemini CLI's event names (its settings.json uses the same hooks shape).
    static let geminiEvents: [AgentSpec.HookEvent] = [
        .init("SessionStart"), .init("SessionEnd"),
        .init("BeforeAgent"), .init("AfterAgent"), .init("Notification"),
    ]

    public static let all: [AgentSpec] = [
        .init(id: "claude", name: "Claude Code", configDir: ".claude",
              configFile: "settings.json", mechanism: .jsonHooks(events: claudeEvents)),
        // Claude-schema forks: same hook payloads, different home dir.
        .init(id: "qwen", name: "Qwen Code", configDir: ".qwen",
              configFile: "settings.json", mechanism: .jsonHooks(events: claudeEvents)),
        .init(id: "qoder", name: "Qoder", configDir: ".qoder",
              configFile: "settings.json", mechanism: .jsonHooks(events: claudeEvents)),
        .init(id: "droid", name: "Droid", configDir: ".factory",
              configFile: "settings.json", mechanism: .jsonHooks(events: claudeEvents)),
        .init(id: "codebuddy", name: "CodeBuddy", configDir: ".codebuddy",
              configFile: "settings.json", mechanism: .jsonHooks(events: claudeEvents)),
        .init(id: "gemini", name: "Gemini CLI", configDir: ".gemini",
              configFile: "settings.json", mechanism: .jsonHooks(events: geminiEvents)),
        .init(id: "cursor", name: "Cursor", configDir: ".cursor", configFile: "hooks.json",
              mechanism: .cursorHooks(events: ["beforeSubmitPrompt", "beforeShellExecution",
                                               "afterFileEdit", "stop"])),
        .init(id: "codex", name: "Codex", configDir: ".codex",
              configFile: "hooks.json", mechanism: .codexHooks(events: codexEvents)),
        .init(id: "kimi", name: "Kimi Code", configDir: ".kimi",
              configFile: "config.toml", mechanism: .kimiTOML(events: claudeEvents)),
        .init(id: "opencode", name: "OpenCode", configDir: ".config/opencode",
              configFile: "opencode.json", mechanism: .opencodePlugin),
    ]

    public static func byID(_ id: String) -> AgentSpec? { all.first { $0.id == id } }

    /// Agents whose config directory exists on this machine.
    public static var detected: [AgentSpec] { all.filter(\.isDetected) }
}
