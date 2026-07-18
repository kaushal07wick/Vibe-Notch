import Foundation

/// One provider's rate-limit windows (e.g. Claude's 5h + 7d).
public struct ProviderUsage: Sendable, Equatable {
    public struct Window: Sendable, Equatable {
        public let label: String        // "5h", "7d"
        public let usedPercentage: Double
        public let resetsAt: Date?
    }
    public let provider: String         // "Claude", "Codex"
    public let windows: [Window]

    /// The window closest to its limit — what the header chip shows.
    public var peak: Window? { windows.max { $0.usedPercentage < $1.usedPercentage } }
}

/// Reads agent usage from local sources. No network, no accounts:
/// - Claude: our status-line script tees `.rate_limits` → cache/rl-claude.json
/// - Codex: last `token_count` event in the newest session rollout JSONL
public enum UsageLoader {
    public static var claudeCacheURL: URL {
        VNPaths.cache.appendingPathComponent("rl-claude.json")
    }

    public static func load() -> [ProviderUsage] {
        var out: [ProviderUsage] = []
        if let claude = loadClaude() { out.append(claude) }
        if let codex = loadCodex() { out.append(codex) }
        return out
    }

    // MARK: Claude

    static func loadClaude(from url: URL? = nil) -> ProviderUsage? {
        guard let data = try? Data(contentsOf: url ?? claudeCacheURL),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let windows = [("five_hour", "5h"), ("seven_day", "7d")].compactMap { key, label -> ProviderUsage.Window? in
            guard let w = obj[key] as? [String: Any] else { return nil }
            let pct = (w["used_percentage"] as? Double) ?? (w["utilization"] as? Double)
            guard let pct else { return nil }
            return .init(label: label, usedPercentage: pct, resetsAt: parseDate(w["resets_at"]))
        }
        return windows.isEmpty ? nil : ProviderUsage(provider: "Claude", windows: windows)
    }

    // MARK: Codex

    static func loadCodex(sessionsDir: URL? = nil) -> ProviderUsage? {
        let dir = sessionsDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        guard let rollout = newestRollout(in: dir),
              let content = try? String(contentsOf: rollout, encoding: .utf8) else { return nil }

        // Last token_count event carries the current rate limits.
        for line in content.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  (obj["type"] as? String) == "event_msg",
                  let payload = obj["payload"] as? [String: Any],
                  (payload["type"] as? String) == "token_count",
                  let limits = payload["rate_limits"] as? [String: Any] else { continue }
            let windows = ["primary", "secondary"].compactMap { key -> ProviderUsage.Window? in
                guard let w = limits[key] as? [String: Any],
                      let pct = w["used_percent"] as? Double else { return nil }
                return .init(label: windowLabel(minutes: w["window_minutes"] as? Int),
                             usedPercentage: pct, resetsAt: parseDate(w["resets_at"]))
            }
            return windows.isEmpty ? nil : ProviderUsage(provider: "Codex", windows: windows)
        }
        return nil
    }

    static func newestRollout(in dir: URL) -> URL? {
        guard let files = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return nil }
        var newest: (URL, Date)?
        for case let url as URL in files where url.lastPathComponent.hasPrefix("rollout-") {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if newest == nil || date > newest!.1 { newest = (url, date) }
        }
        return newest?.0
    }

    // MARK: Helpers

    static func windowLabel(minutes: Int?) -> String {
        guard let minutes else { return "now" }
        if minutes >= 1440 { return "\(minutes / 1440)d" }
        if minutes >= 60 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    static func parseDate(_ value: Any?) -> Date? {
        if let epoch = value as? Double { return Date(timeIntervalSince1970: epoch) }
        if let s = value as? String {
            if let epoch = Double(s) { return Date(timeIntervalSince1970: epoch) }
            return ISO8601DateFormatter().date(from: s)
        }
        return nil
    }
}
