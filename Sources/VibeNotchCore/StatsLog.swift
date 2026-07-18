import Foundation

/// Tiny local analytics: per-day counters (approvals, denials, sessions) in
/// ~/.vibenotch/data/stats-YYYY-MM.json. No network, trivially inspectable.
public enum StatsLog {
    /// All-time counter totals across every month file (mascot levels, recaps).
    public static func totals() -> [String: Int] {
        var out: [String: Int] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(at: VNPaths.data, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.lastPathComponent.hasPrefix("stats-") {
            guard let root = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: [String: Int]] else { continue }
            for day in root.values {
                for (key, count) in day { out[key, default: 0] += count }
            }
        }
        return out
    }

    /// Today's counters (daily recap card).
    public static func today(_ date: Date = Date()) -> [String: Int] {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let month = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        let day = String(format: "%02d", comps.day ?? 0)
        let url = VNPaths.data.appendingPathComponent("stats-\(month).json")
        let root = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: [String: Int]]
        return root?[day] ?? [:]
    }

    /// Mascot level from lifetime activity: 1…5.
    public static func mascotLevel(totals: [String: Int]) -> Int {
        let score = (totals["approved"] ?? 0) + (totals["autoApproved"] ?? 0) + (totals["sessions"] ?? 0)
        switch score {
        case ..<50: return 1
        case ..<250: return 2
        case ..<1000: return 3
        case ..<5000: return 4
        default: return 5
        }
    }

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
