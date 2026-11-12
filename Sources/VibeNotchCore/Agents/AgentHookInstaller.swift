import Foundation

/// Wires `vibenotch-hook` into one agent's config, per its mechanism.
/// Every edit backs up changed existing files and is idempotent; uninstall
/// removes only our entries and leaves everything else intact.
public struct AgentHookInstaller: Sendable {
    public let spec: AgentSpec
    private let configDirectory: URL
    private let hookBinary: URL
    public init(_ spec: AgentSpec, configDirectory: URL? = nil, hookBinary: URL? = nil) {
        self.spec = spec
        self.configDirectory = configDirectory ?? spec.configDirURL
        self.hookBinary = hookBinary ?? VNPaths.bin.appendingPathComponent("vibenotch-hook")
    }
    private var configFileURL: URL { configDirectory.appendingPathComponent(spec.configFile) }

    static let marker = "vibenotch-hook"

    /// Fail-open shell wrapper: run the hook only if present, always exit 0.
    var hookCommand: String {
        #"/bin/sh -c '[ -x "$HOME/.vibenotch/bin/vibenotch-hook" ] && "$HOME/.vibenotch/bin/vibenotch-hook" --source \#(spec.id); exit 0'"#
    }

    // MARK: Public API

    public var isConnected: Bool { health.state == .configured }

    public func connect(hookBinarySource: URL) throws {
        try connectionPlan(connecting: true, hookBinarySource: hookBinarySource).apply()
    }

    public func disconnect() throws {
        try connectionPlan(connecting: false).apply()
    }

    /// Where the OpenCode plugin JS is copied from (set by the app at launch
    /// to its bundle Resources; falls back to ~/.vibenotch/bin for CLI use).
    public static nonisolated(unsafe) var pluginSourceDir: URL?

    /// Replace the installed hook whenever it differs from the one in this
    /// bundle. The skew check only fires on a protocol *version* change, and
    /// that string moves at release time — so every fix to the hook between
    /// releases sat in the bundle unused while the old binary kept running.
    /// Byte comparison needs no version to maintain.
    public static func refreshHookBinary(from source: URL, destination: URL? = nil) {
        let dest = destination ?? VNPaths.bin.appendingPathComponent("vibenotch-hook")
        guard FileManager.default.fileExists(atPath: source.path),
              !FileManager.default.contentsEqual(atPath: source.path, andPath: dest.path)
        else { return }
        try? installHookBinary(from: source, destination: dest)
    }

    public static func installHookBinary(from source: URL, destination: URL? = nil) throws {
        if destination == nil { try VNPaths.ensure() }
        let dest = destination ?? VNPaths.bin.appendingPathComponent("vibenotch-hook")
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: source, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
    }

    // MARK: Claude-schema settings.json (Claude, forks, Gemini)

    /// Pure transform: settings with our hook groups added. Idempotent.
    static func jsonHooksInstalled(into settings: [String: Any],
                                   events: [AgentSpec.HookEvent],
                                   command: String) -> [String: Any] {
        var out = Self.jsonHooksUninstalled(from: settings)
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
            guard let original = value as? [[String: Any]] else { continue }
            let groups = original.compactMap { group -> [String: Any]? in
                guard let entries = group["hooks"] as? [[String: Any]] else { return group }
                let remaining = entries.filter { !(($0["command"] as? String)?.contains(marker) == true) }
                guard remaining.count != entries.count else { return group }
                guard !remaining.isEmpty else { return nil }
                var kept = group; kept["hooks"] = remaining
                return kept
            }
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

    /// Pure transform for Cursor's flat `hooks[event] = [{command}]` shape.
    static func cursorHooksInstalled(into root: [String: Any],
                                     events: [String], command: String) -> [String: Any] {
        var out = Self.cursorHooksUninstalled(from: root)
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

    private var codexConfigTOMLURL: URL { configDirectory.appendingPathComponent("config.toml") }

    /// Pure transform: ensure `[features]` contains `hooks = true`.
    static func codexFeatureEnabled(in toml: String) -> String {
        var lines = toml.components(separatedBy: "\n")
        var inFeatures = false
        for (i, line) in lines.enumerated() {
            let trimmed = String(line.split(separator: "#", maxSplits: 1).first ?? "").trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { inFeatures = trimmed == "[features]" }
            if inFeatures && trimmed.filter({ !$0.isWhitespace }).hasPrefix("hooks=") {
                lines[i] = "hooks = true"
                return lines.joined(separator: "\n")
            }
        }
        if let idx = lines.firstIndex(where: { String($0.split(separator: "#", maxSplits: 1).first ?? "").trimmingCharacters(in: .whitespaces) == "[features]" }) {
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
        configDirectory.appendingPathComponent("plugins/vibenotch.js")
    }

    /// Pure transform: add our plugin path to `plugin`. Idempotent.
    static func opencodeRegistered(into root: [String: Any], pluginPath: String) -> [String: Any] {
        var out = Self.opencodeUnregistered(from: root)
        var plugins = out["plugin"] as? [String] ?? []
        plugins.append(pluginPath)
        out["plugin"] = plugins
        return out
    }

    /// Pure transform: remove only our plugin entry.
    static func opencodeUnregistered(from root: [String: Any]) -> [String: Any] {
        var out = root
        guard var plugins = out["plugin"] as? [String] else { return out }
        plugins.removeAll(where: isOurPlugin)
        if plugins.isEmpty { out.removeValue(forKey: "plugin") } else { out["plugin"] = plugins }
        return out
    }

}

extension AgentHookInstaller {
    private var expectedEvents: [String] {
        switch spec.mechanism {
        case .jsonHooks(let events), .codexHooks(let events), .kimiTOML(let events): return events.map(\.name)
        case .cursorHooks(let events): return events
        case .opencodePlugin: return ["plugin"]
        }
    }

    public var health: HookConnectionHealth {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configFileURL.path) else {
            return HookConnectionHealth(state: .notConnected, issues: [], installedEvents: [])
        }
        do {
            let data = try Data(contentsOf: configFileURL)
            var installed: [String] = [], correct: [String] = [], issues: [String] = []
            switch spec.mechanism {
            case .jsonHooks(let events), .codexHooks(let events):
                let root = try configurationJSON(data)
                let hooks = root["hooks"] as? [String: Any] ?? [:]
                for (name, value) in hooks {
                    let groups = value as? [[String: Any]] ?? []
                    let commands = groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }.compactMap { $0["command"] as? String }
                    if commands.contains(where: { $0.contains(Self.marker) }) { installed.append(name) }
                    guard let event = events.first(where: { $0.name == name }) else { continue }
                    if groups.contains(where: { group in
                        guard (group["matcher"] as? String ?? "*") == event.matcher else { return false }
                        return (group["hooks"] as? [[String: Any]])?.contains { hook in
                            hook["type"] as? String == "command" && hook["command"] as? String == hookCommand
                                && hook["timeout"] as? Int == event.timeout
                        } == true
                    }) { correct.append(name) }
                }
                if case .codexHooks = spec.mechanism, !installed.isEmpty {
                    let toml = (try? String(contentsOf: codexConfigTOMLURL, encoding: .utf8)) ?? ""
                    if !Self.codexHooksEnabled(in: toml) { issues.append("Codex hooks feature is not enabled in config.toml.") }
                }
            case .cursorHooks:
                let root = try configurationJSON(data)
                let hooks = root["hooks"] as? [String: Any] ?? [:]
                for (name, value) in hooks {
                    let commands = (value as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
                    if commands.contains(where: { $0.contains(Self.marker) }) { installed.append(name) }
                    if commands.contains(hookCommand) { correct.append(name) }
                }
            case .kimiTOML:
                guard let text = String(data: data, encoding: .utf8) else { throw HookChangePlan.ChangeError.invalidConfiguration(configFileURL.path) }
                let blocks = text.components(separatedBy: Self.kimiMarker).dropFirst()
                for event in expectedEvents {
                    if blocks.contains(where: { $0.contains("event = \"\(event)\"") && $0.contains(Self.marker) }) { installed.append(event) }
                    if blocks.contains(where: { $0.contains("event = \"\(event)\"") && $0.contains(hookCommand) }) { correct.append(event) }
                }
            case .opencodePlugin:
                let root = try configurationJSON(data)
                let plugins = root["plugin"] as? [String] ?? []
                if plugins.contains(where: Self.isOurPlugin) { installed = ["plugin"] }
                if plugins.contains(opencodePluginURL.path), fm.fileExists(atPath: opencodePluginURL.path) { correct = ["plugin"] }
            }
            guard !installed.isEmpty else { return HookConnectionHealth(state: .notConnected, issues: [], installedEvents: []) }
            let missing = expectedEvents.filter { !correct.contains($0) }
            if !missing.isEmpty { issues.append("Missing or outdated entries: " + missing.joined(separator: ", ") + ".") }
            if !fm.isExecutableFile(atPath: hookBinary.path) { issues.append("The installed hook helper is missing or is not executable.") }
            return HookConnectionHealth(state: issues.isEmpty ? .configured : .needsRepair, issues: issues, installedEvents: installed.sorted())
        } catch {
            return HookConnectionHealth(state: .needsRepair, issues: [error.localizedDescription], installedEvents: [])
        }
    }

    /// Both the preview and installation use this one transformation path.
    public func connectionPlan(connecting: Bool, hookBinarySource: URL? = nil) throws -> HookChangePlan {
        let fm = FileManager.default
        func data(at url: URL) throws -> Data? { fm.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil }
        func json(_ root: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        }
        let before = try data(at: configFileURL)
        var changes: [HookChangePlan.FileChange] = []
        var after: Data?
        switch spec.mechanism {
        case .jsonHooks(let events), .codexHooks(let events):
            let root = try configurationJSON(before)
            after = try json(connecting ? Self.jsonHooksInstalled(into: root, events: events, command: hookCommand) : Self.jsonHooksUninstalled(from: root))
            if case .codexHooks = spec.mechanism {
                let old = try data(at: codexConfigTOMLURL)
                guard old == nil || String(data: old!, encoding: .utf8) != nil else { throw HookChangePlan.ChangeError.invalidConfiguration(codexConfigTOMLURL.path) }
                let text = String(decoding: old ?? Data(), as: UTF8.self)
                let clean = Self.withoutOurNotify(text)
                let updated = connecting ? Self.codexFeatureEnabled(in: clean) : clean
                if connecting || old != nil { changes.append(.init(url: codexConfigTOMLURL, before: old, after: Data(updated.utf8))) }
            }
        case .cursorHooks(let events):
            let root = try configurationJSON(before)
            after = try json(connecting ? Self.cursorHooksInstalled(into: root, events: events, command: hookCommand) : Self.cursorHooksUninstalled(from: root))
        case .kimiTOML(let events):
            guard before == nil || String(data: before!, encoding: .utf8) != nil else { throw HookChangePlan.ChangeError.invalidConfiguration(configFileURL.path) }
            let text = String(decoding: before ?? Data(), as: UTF8.self)
            after = Data((connecting ? Self.kimiInstalled(into: text, events: events, command: hookCommand) : Self.kimiUninstalled(from: text)).utf8)
        case .opencodePlugin:
            let root = try configurationJSON(before)
            after = try json(connecting ? Self.opencodeRegistered(into: root, pluginPath: opencodePluginURL.path) : Self.opencodeUnregistered(from: root))
            let old = try data(at: opencodePluginURL)
            if connecting {
                let source = Self.pluginSourceDir?.appendingPathComponent("vibenotch-opencode.js") ?? VNPaths.bin.appendingPathComponent("vibenotch-opencode.js")
                guard let content = try data(at: source) else { throw HookChangePlan.ChangeError.missingResource(source.path) }
                changes.append(.init(url: opencodePluginURL, before: old, after: content))
            } else { changes.append(.init(url: opencodePluginURL, before: old, after: nil)) }
        }
        if connecting || before != nil { changes.insert(.init(url: configFileURL, before: before, after: after), at: 0) }
        if connecting, let source = hookBinarySource {
            guard let content = try data(at: source) else { throw HookChangePlan.ChangeError.missingResource(source.path) }
            changes.insert(.init(url: hookBinary, before: try data(at: hookBinary), after: content, executable: true, isText: false), at: 0)
        }
        return HookChangePlan(agentName: spec.name, connecting: connecting, events: expectedEvents, changes: changes)
    }

    private func configurationJSON(_ data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw HookChangePlan.ChangeError.invalidConfiguration(configFileURL.path) }
        if let value = root["hooks"] {
            guard let hooks = value as? [String: Any] else { throw HookChangePlan.ChangeError.invalidConfiguration(configFileURL.path) }
            for value in hooks.values {
                guard let groups = value as? [[String: Any]] else { throw HookChangePlan.ChangeError.invalidConfiguration(configFileURL.path) }
                if case .cursorHooks = spec.mechanism { continue }
                for group in groups where group["hooks"] != nil {
                    guard group["hooks"] is [[String: Any]] else { throw HookChangePlan.ChangeError.invalidConfiguration(configFileURL.path) }
                }
            }
        }
        if case .opencodePlugin = spec.mechanism, let value = root["plugin"], !(value is [String]) { throw HookChangePlan.ChangeError.invalidConfiguration(configFileURL.path) }
        return root
    }

    private static func isOurPlugin(_ path: String) -> Bool { path.hasSuffix("/plugins/vibenotch.js") }

    private static func codexHooksEnabled(in toml: String) -> Bool {
        var inFeatures = false
        for line in toml.components(separatedBy: "\n") {
            let text = String(line.split(separator: "#", maxSplits: 1).first ?? "").trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("[") { inFeatures = text == "[features]" }
            if inFeatures && text.filter({ !$0.isWhitespace }) == "hooks=true" { return true }
        }
        return false
    }
}

public enum AgentConnections {
    /// True when any agent has our hook installed.
    public static var anyConnected: Bool {
        Agents.all.contains { AgentHookInstaller($0).isConnected }
    }
}
