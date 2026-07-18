import Foundation

/// Wires `vibenotch-hook` into Codex's `~/.codex/config.toml` via `notify`.
/// Codex `notify` is notification-only (no blocking approval), so Codex sessions
/// show activity/waiting in the notch but can't be approved from it.
public enum CodexInstaller {
    static let marker = "vibenotch-hook"

    public static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml")
    }

    static var backupURL: URL { configURL.appendingPathExtension("vibenotch.bak") }

    static var notifyLine: String {
        let bin = VNPaths.bin.appendingPathComponent("vibenotch-hook").path
        return "notify = [\"\(bin)\", \"--source\", \"codex\"]"
    }

    public static var isConnected: Bool {
        ((try? String(contentsOf: configURL, encoding: .utf8)) ?? "").contains(marker)
    }

    public static func connect(hookBinarySource: URL) throws {
        try VNPaths.ensure()
        let dest = VNPaths.bin.appendingPathComponent("vibenotch-hook")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: hookBinarySource, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)

        let text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        guard !text.contains(marker) else { return } // idempotent
        backupOnce(text)
        // Drop any existing top-level notify (TOML forbids duplicate keys); ours goes first.
        var lines = text.components(separatedBy: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("notify =")
        }
        lines.insert(notifyLine, at: 0)
        try write(lines.joined(separator: "\n"))
    }

    public static func disconnect() throws {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\n").filter { !$0.contains(marker) }
        try write(lines.joined(separator: "\n"))
    }

    private static func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func backupOnce(_ text: String) {
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        try? text.write(to: backupURL, atomically: true, encoding: .utf8)
    }
}
