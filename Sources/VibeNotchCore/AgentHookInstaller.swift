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
        return text.contains(Self.marker)
    }

    /// Install the hook binary (shared) and wire this agent's config.
    public func connect(hookBinarySource: URL) throws {
        try Self.installHookBinary(from: hookBinarySource)
        switch spec.mechanism {
        case .jsonHooks(let events): try connectJSONHooks(events: events)
        case .cursorHooks(let events): try connectCursorHooks(events: events)
        case .codexNotify: try connectCodexNotify()
        case .kimiTOML(let events): try connectKimiTOML(events: events)
        }
    }

    public func disconnect() throws {
        switch spec.mechanism {
        case .jsonHooks: try disconnectJSONHooks()
        case .cursorHooks: try disconnectCursorHooks()
        case .codexNotify: try disconnectCodexNotify()
        case .kimiTOML: try disconnectKimiTOML()
        }
    }

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
                groups.append(["matcher": "*", "hooks": [hook]])
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

    // MARK: Codex config.toml notify

    private var codexNotifyLine: String {
        let bin = VNPaths.bin.appendingPathComponent("vibenotch-hook").path
        return "notify = [\"\(bin)\", \"--source\", \"codex\"]"
    }

    private func connectCodexNotify() throws {
        let text = (try? String(contentsOf: spec.configFileURL, encoding: .utf8)) ?? ""
        guard !text.contains(Self.marker) else { return }
        backupOnce()
        // TOML forbids duplicate top-level keys — replace any existing notify.
        var lines = text.components(separatedBy: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("notify =")
        }
        lines.insert(codexNotifyLine, at: 0)
        try writeText(lines.joined(separator: "\n"))
    }

    private func disconnectCodexNotify() throws {
        guard let text = try? String(contentsOf: spec.configFileURL, encoding: .utf8) else { return }
        try writeText(text.components(separatedBy: "\n").filter { !$0.contains(Self.marker) }
            .joined(separator: "\n"))
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

    // MARK: File IO

    private func readJSON() -> [String: Any]? {
        guard let data = try? Data(contentsOf: spec.configFileURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func writeJSON(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: spec.configDirURL, withIntermediateDirectories: true)
        try data.write(to: spec.configFileURL, options: .atomic)
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
