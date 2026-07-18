import Foundation

/// Tiny local analytics: per-day counters (approvals, denials, sessions) in
/// ~/.vibenotch/data/stats-YYYY-MM.json. No network, trivially inspectable.
public enum StatsLog {
    public static func bump(_ key: String, on date: Date = Date()) {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let month = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        let day = String(format: "%02d", comps.day ?? 0)
        let url = VNPaths.data.appendingPathComponent("stats-\(month).json")

        var root = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: [String: Int]] ?? [:]
        var counts = root[day] ?? [:]
        counts[key, default: 0] += 1
        root[day] = counts
        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
