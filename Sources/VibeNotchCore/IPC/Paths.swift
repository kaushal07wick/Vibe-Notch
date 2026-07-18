import Foundation

/// Filesystem layout under `~/.vibenotch`, mirroring the live app's `~/.vibe-island`.
public enum VNPaths {
    public static let home = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".vibenotch")
    public static let bin = home.appendingPathComponent("bin")
    public static let run = home.appendingPathComponent("run")
    public static let cache = home.appendingPathComponent("cache")
    public static let data = home.appendingPathComponent("data")

    /// Overridable via VIBENOTCH_SOCKET (used by the E2E test harness).
    public static var socket: URL {
        if let override = ProcessInfo.processInfo.environment["VIBENOTCH_SOCKET"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return run.appendingPathComponent("vibenotch.sock")
    }
    public static let pid = run.appendingPathComponent("vibenotch.pid")

    /// Create the directory tree if missing. Idempotent.
    public static func ensure() throws {
        for dir in [home, bin, run, cache, data] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
