import Foundation

public typealias CodexQuestion = CodexPendingQuestion

public enum CodexQuestionWatcher {
    /// Unanswered questions in recently active Codex transcripts, newest file first.
    public static func scan() -> [CodexQuestion] {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        var files: [(URL, Date)] = []
        let cal = Calendar.current
        for back in 0...1 {
            guard let day = cal.date(byAdding: .day, value: -back, to: Date()) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: day)
            let dir = root.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year!, c.month!, c.day!))
            for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            where f.pathExtension == "jsonl" {
                let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if m > Date().addingTimeInterval(-6 * 3600) { files.append((f, m)) }
            }
        }
        var out: [CodexQuestion] = []
        for (url, _) in files.sorted(by: { $0.1 > $1.1 }).prefix(8) {
            if let q = pending(in: url) { out.append(q) }
        }
        return out
    }

    static func pending(in url: URL) -> CodexQuestion? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 1_500_000
        try? handle.seek(toOffset: size > window ? size - window : 0)
        guard let data = try? handle.readToEnd() else { return nil }

        guard let metadata = metadata(of: url) else { return nil }
        return CodexQuestionParser.pending(in: data, sessionID: metadata.id, cwd: metadata.cwd)
    }

    private static func metadata(of url: URL) -> (id: String, cwd: String)? {
        guard let handle = try? FileHandle(forReadingFrom: url), let head = try? handle.read(upToCount: 131_072) else { return nil }
        try? handle.close()
        guard let line = head.split(separator: 0x0A).first,
              let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { return nil }
        guard let payload = obj["payload"] as? [String: Any], let id = payload["id"] as? String,
              let cwd = payload["cwd"] as? String else { return nil }
        return (id, cwd)
    }
}
