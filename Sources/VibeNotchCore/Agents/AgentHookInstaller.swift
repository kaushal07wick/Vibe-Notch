import Foundation

/// Wires `vibenotch-hook` into one agent's config, per its mechanism.
/// Every edit backs up the target file once and is idempotent; uninstall
/// removes only our entries and leaves everything else intact.
public struct AgentHookInstaller: Sendable {
    public let spec: AgentSpec
    public init(_ spec: AgentSpec) { self.spec = spec }

    static let marker = "vibenotch-hook"

    /// Fail-open shell wrapper: run the hook only if present, always exit 0.
    var hookCommand: String {
        #"/bin/sh -c '[ -x "$HOME/.vibenotch/bin/vibenotch-hook" ] && "$HOME/.vibenotch/bin/vibenotch-hook" --source \#(spec.id); exit 0'"#
    }

    var backupURL: URL { spec.configFileURL.appendingPathExtension("vibenotch.bak") }

    // MARK: Public API

    public var isConnected: Bool {
        guard let text = try? String(contentsOf: spec.configFileURL, encoding: .utf8) else { return false }
        return text.contains("vibenotch") // matches both the hook command and the plugin path
    }

    /// Install the hook binary (shared) and wire this agent's config.
    public func connect(hookBinarySource: URL) throws {
        try Self.installHookBinary(from: hookBinarySource)
        switch spec.mechanism {
        case .jsonHooks(let events): try connectJSONHooks(events: events)
        case .cursorHooks(let events): try connectCursorHooks(events: events)
        case .codexHooks(let events): try connectCodexHooks(events: events)
        case .kimiTOML(let events): try connectKimiTOML(events: events)
        case .opencodePlugin: try connectOpenCodePlugin()
        }
    }

    public func disconnect() throws {
        switch spec.mechanism {
        case .jsonHooks: try disconnectJSONHooks()
        case .cursorHooks: try disconnectCursorHooks()
        case .codexHooks: try disconnectCodexHooks()
        case .kimiTOML: try disconnectKimiTOML()
        case .opencodePlugin: try disconnectOpenCodePlugin()
        }
    }

    /// Where the OpenCode plugin JS is copied from (set by the app at launch
    /// to its bundle Resources; falls back to ~/.vibenotch/bin for CLI use).
    public static nonisolated(unsafe) var pluginSourceDir: URL?

    /// Re-apply the current event set if already connected (picks up newly
    /// added events without the user re-clicking Connect). Idempotent.
    public func reconcile() {
        guard isConnected else { return }
        if case .jsonHooks(let events) = spec.mechanism {
            guard let settings = readJSON() else { return }
            try? writeJSON(Self.jsonHooksInstalled(into: settings, events: events, command: hookCommand))
        }
    }

    public static func installHookBinary(from source: URL) throws {
        try VNPaths.ensure()
        let dest = VNPaths.bin.appendingPathComponent("vibenotch-hook")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: source, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
    }

    // MARK: Claude-schema settings.json (Claude, forks, Gemini)

    private func connectJSONHooks(events: [AgentSpec.HookEvent]) throws {
        let settings = readJSON() ?? [:]
        backupOnce()
        try writeJSON(Self.jsonHooksInstalled(into: settings, events: events, command: hookCommand))
    }

    private func disconnectJSONHooks() throws {
        guard let settings = readJSON() else { return }
        try writeJSON(Self.jsonHooksUninstalled(from: settings))
    }

    /// Pure transform: settings with our hook groups added. Idempotent.
    static func jsonHooksInstalled(into settings: [String: Any],
                                   events: [AgentSpec.HookEvent],
                                   command: String) -> [String: Any] {
        var out = settings
        var hooks = out["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = hooks[event.name] as? [[String: Any]] ?? []
            if !groups.contains(where: groupIsOurs) {
                var hook: [String: Any] = ["type": "command", "command": command]
                if let timeout = event.timeout { hook["timeout"] = timeout }
                groups.append(["matcher": event.matcher, "hooks": [hook]])
            }
            hooks[event.name] = groups
        }
        out["hooks"] = hooks
        return out
    }

    /// Pure transform: settings with only our hook groups removed.
    static func jsonHooksUninstalled(from settings: [String: Any]) -> [String: Any] {
        var out = settings
        guard var hooks = out["hooks"] as? [String: Any] else { return out }
        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups.removeAll(where: groupIsOurs)
            if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
        }
        if hooks.isEmpty { out.removeValue(forKey: "hooks") } else { out["hooks"] = hooks }
        return out
    }

    private static func groupIsOurs(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]])?.contains {
            ($0["command"] as? String)?.contains(marker) == true
        } == true
    }

    // MARK: Cursor hooks.json

    private func connectCursorHooks(events: [String]) throws {
        let root = readJSON() ?? [:]
        backupOnce()
        try writeJSON(Self.cursorHooksInstalled(into: root, events: events, command: hookCommand))
    }

    private func disconnectCursorHooks() throws {
        guard let root = readJSON() else { return }
        try writeJSON(Self.cursorHooksUninstalled(from: root))
    }

    /// Pure transform for Cursor's flat `hooks[event] = [{command}]` shape.
    static func cursorHooksInstalled(into root: [String: Any],
                                     events: [String], command: String) -> [String: Any] {
        var out = root
        if out["version"] == nil { out["version"] = 1 }
        var hooks = out["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var entries = hooks[event] as? [[String: Any]] ?? []
            if !entries.contains(where: { ($0["command"] as? String)?.contains(marker) == true }) {
                entries.append(["command": command])
            }
            hooks[event] = entries
        }
        out["hooks"] = hooks
        return out
    }

    static func cursorHooksUninstalled(from root: [String: Any]) -> [String: Any] {
        var out = root
        guard var hooks = out["hooks"] as? [String: Any] else { return out }
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll { ($0["command"] as? String)?.contains(marker) == true }
            if entries.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = entries }
        }
        if hooks.isEmpty { out.removeValue(forKey: "hooks") } else { out["hooks"] = hooks }
        return out
    }

    // MARK: Codex hooks.json + feature flag

    private var codexConfigTOMLURL: URL { spec.configDirURL.appendingPathComponent("config.toml") }

    private func connectCodexHooks(events: [AgentSpec.HookEvent]) throws {
        // 1. Claude-shaped hooks object into ~/.codex/hooks.json.
        let hooks = readJSON() ?? [:]
        backupOnce()
        try writeJSON(Self.jsonHooksInstalled(into: hooks, events: events, command: hookCommand))

        // 2. Enable the hooks feature + drop our legacy notify line in config.toml.
        if let toml = try? String(contentsOf: codexConfigTOMLURL, encoding: .utf8) {
            let updated = Self.codexFeatureEnabled(in: Self.withoutOurNotify(toml))
            if updated != toml { try updated.write(to: codexConfigTOMLURL, atomically: true, encoding: .utf8) }
        }
    }

    private func disconnectCodexHooks() throws {
        if let hooks = readJSON() {
            try writeJSON(Self.jsonHooksUninstalled(from: hooks))
        }
        if let toml = try? String(contentsOf: codexConfigTOMLURL, encoding: .utf8) {
            let updated = Self.withoutOurNotify(toml)
            if updated != toml { try updated.write(to: codexConfigTOMLURL, atomically: true, encoding: .utf8) }
        }
    }

    /// Pure transform: ensure `[features]` contains `hooks = true`.
    static func codexFeatureEnabled(in toml: String) -> String {
        var lines = toml.components(separatedBy: "\n")
        var inFeatures = false
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { inFeatures = trimmed == "[features]" }
            if inFeatures && trimmed.replacingOccurrences(of: " ", with: "").hasPrefix("hooks=") {
                lines[i] = "hooks = true"
                return lines.joined(separator: "\n")
            }
        }
        if let idx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[features]" }) {
            lines.insert("hooks = true", at: idx + 1)
            return lines.joined(separator: "\n")
        }
        return toml + "\n[features]\nhooks = true\n"
    }

    /// Pure transform: remove our old notify wiring (pre-hooks era).
    static func withoutOurNotify(_ toml: String) -> String {
        toml.components(separatedBy: "\n")
            .filter { !($0.contains("notify") && $0.contains(marker)) }
            .joined(separator: "\n")
    }

    // MARK: Kimi config.toml [[hooks]] blocks

    static let kimiMarker = "# vibenotch: managed hook — do not edit"

    private func connectKimiTOML(events: [AgentSpec.HookEvent]) throws {
        let text = (try? String(contentsOf: spec.configFileURL, encoding: .utf8)) ?? ""
        guard !text.contains(Self.marker) else { return } // idempotent
        backupOnce()
        try writeText(Self.kimiInstalled(into: text, events: events, command: hookCommand))
    }

    private func disconnectKimiTOML() throws {
        guard let text = try? String(contentsOf: spec.configFileURL, encoding: .utf8) else { return }
        try writeText(Self.kimiUninstalled(from: text))
    }

    /// Pure transform: append one marked `[[hooks]]` block per event.
    static func kimiInstalled(into text: String, events: [AgentSpec.HookEvent], command: String) -> String {
        var out = Self.kimiUninstalled(from: text)
        if !out.isEmpty && !out.hasSuffix("\n\n") { out += out.hasSuffix("\n") ? "\n" : "\n\n" }
        for event in events {
            out += """
            \(kimiMarker)
            [[hooks]]
            event = "\(event.name)"
            matcher = "*"
            command = '''\(command)'''
            timeout = \(event.timeout ?? 45)


            """
        }
        return out
    }

    /// Pure transform: drop every marked block (marker line through blank line).
    static func kimiUninstalled(from text: String) -> String {
        var out: [String] = []
        var skipping = false
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces) == kimiMarker { skipping = true; continue }
            if skipping {
                if line.trimmingCharacters(in: .whitespaces).isEmpty { skipping = false }
                continue
            }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }

    // MARK: OpenCode JS plugin

    private var opencodePluginURL: URL {
        spec.configDirURL.appendingPathComponent("plugins/vibenotch.js")
    }

    private func connectOpenCodePlugin() throws {
        // Copy the plugin JS next to OpenCode's config.
        guard let src = Self.pluginSourceDir?.appendingPathComponent("vibenotch-opencode.js"),
              FileManager.default.fileExists(atPath: src.path) else { return }
        try FileManager.default.createDirectory(at: opencodePluginURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: opencodePluginURL)
        try FileManager.default.copyItem(at: src, to: opencodePluginURL)

        // Register in opencode.json's `plugin` array.
        let root = readJSON() ?? [:]
        backupOnce()
        try writeJSON(Self.opencodeRegistered(into: root, pluginPath: opencodePluginURL.path))
    }

    private func disconnectOpenCodePlugin() throws {
        try? FileManager.default.removeItem(at: opencodePluginURL)
        guard let root = readJSON() else { return }
        try writeJSON(Self.opencodeUnregistered(from: root))
    }

    /// Pure transform: add our plugin path to `plugin`. Idempotent.
    static func opencodeRegistered(into root: [String: Any], pluginPath: String) -> [String: Any] {
        var out = root
        var plugins = out["plugin"] as? [String] ?? []
        if !plugins.contains(where: { $0.contains("vibenotch") }) { plugins.append(pluginPath) }
        out["plugin"] = plugins
        return out
    }

    /// Pure transform: remove only our plugin entry.
    static func opencodeUnregistered(from root: [String: Any]) -> [String: Any] {
        var out = root
        guard var plugins = out["plugin"] as? [String] else { return out }
        plugins.removeAll { $0.contains("vibenotch") }
        if plugins.isEmpty { out.removeValue(forKey: "plugin") } else { out["plugin"] = plugins }
        return out
    }

    // MARK: File IO

    private func readJSON() -> [String: Any]? { ConfigJSON.read(spec.configFileURL) }

    private func writeJSON(_ object: [String: Any]) throws {
        try ConfigJSON.write(object, to: spec.configFileURL)
    }

    private func writeText(_ text: String) throws {
        try FileManager.default.createDirectory(at: spec.configDirURL, withIntermediateDirectories: true)
        try text.write(to: spec.configFileURL, atomically: true, encoding: .utf8)
    }

    private func backupOnce() {
        guard !FileManager.default.fileExists(atPath: backupURL.path),
              FileManager.default.fileExists(atPath: spec.configFileURL.path) else { return }
        try? FileManager.default.copyItem(at: spec.configFileURL, to: backupURL)
    }
}

public enum AgentConnections {
    /// True when any agent has our hook installed.
    public static var anyConnected: Bool {
        Agents.all.contains { AgentHookInstaller($0).isConnected }
    }
}
