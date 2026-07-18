import Foundation

/// Wires `vibenotch-hook` into `~/.claude/settings.json`, mirroring how the live
/// Vibe Island installs its bridge: one fail-open command per event, with
/// `PermissionRequest` given a long timeout so it can block for a GUI decision.
public enum ClaudeInstaller {
    /// Fail-open wrapper: run the hook only if present, always exit 0.
    public static let hookCommand =
        #"/bin/sh -c '[ -x "$HOME/.vibenotch/bin/vibenotch-hook" ] && "$HOME/.vibenotch/bin/vibenotch-hook" --source claude; exit 0'"#

    /// Substring that uniquely identifies our hook entries (distinct from vibe-island-bridge).
    static let marker = "vibenotch-hook"

    /// Events we register. PermissionRequest blocks for approval; the rest are notifications.
    static let events: [(name: String, timeout: Int?)] = [
        ("PermissionRequest", 86_400),
        ("Notification", nil),
        ("Stop", nil),
        ("SessionStart", nil),
    ]

    public static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    static var backupURL: URL {
        settingsURL.appendingPathExtension("vibenotch.bak")
    }

    // MARK: Pure transforms (unit-testable)

    static func hookGroup(timeout: Int?) -> [String: Any] {
        var hook: [String: Any] = ["type": "command", "command": hookCommand]
        if let timeout { hook["timeout"] = timeout }
        return ["matcher": "*", "hooks": [hook]]
    }

    static func groupHasOurHook(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]])?.contains {
            ($0["command"] as? String)?.contains(marker) == true
        } == true
    }

    /// Return `settings` with our hooks added. Idempotent.
    public static func installed(into settings: [String: Any]) -> [String: Any] {
        var out = settings
        var hooks = out["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = hooks[event.name] as? [[String: Any]] ?? []
            if !groups.contains(where: groupHasOurHook) {
                groups.append(hookGroup(timeout: event.timeout))
            }
            hooks[event.name] = groups
        }
        out["hooks"] = hooks
        return out
    }

    /// Return `settings` with only our hooks removed, leaving everything else intact.
    public static func uninstalled(from settings: [String: Any]) -> [String: Any] {
        var out = settings
        guard var hooks = out["hooks"] as? [String: Any] else { return out }
        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups.removeAll(where: groupHasOurHook)
            if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
        }
        if hooks.isEmpty { out.removeValue(forKey: "hooks") } else { out["hooks"] = hooks }
        return out
    }

    // MARK: File operations

    public static var isConnected: Bool {
        guard let settings = readSettings(),
              let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]])?.contains(where: groupHasOurHook) == true
        }
    }

    /// Install the hook binary and wire settings.json. Backs up settings.json once.
    public static func connect(hookBinarySource: URL) throws {
        try VNPaths.ensure()
        let dest = VNPaths.bin.appendingPathComponent("vibenotch-hook")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: hookBinarySource, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)

        let settings = readSettings() ?? [:]
        backupOnce(settings)
        try writeSettings(installed(into: settings))
    }

    /// Remove our hooks from settings.json. Leaves the installed binary in place.
    public static func disconnect() throws {
        guard let settings = readSettings() else { return }
        try writeSettings(uninstalled(from: settings))
    }

    // MARK: IO helpers

    static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    static func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: settingsURL, options: .atomic)
    }

    static func backupOnce(_ settings: [String: Any]) {
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted]) {
            try? data.write(to: backupURL)
        }
    }
}
