import Foundation

/// Codex asks its multiple-choice questions inside its own TUI and fires no hook for them,
/// but every ask lands in the session transcript as a `request_user_input` call that has no
/// output until it is answered. Reading that is how the notch learns a question is open.
struct CodexQuestion: Equatable, Identifiable {
    struct Item: Equatable { let title: String; let options: [String] }
    let id: String          // call_id
    let cwd: String
    let items: [Item]
    /// `request_user_input_async`: queued in the TUI ("⇧← to answer") instead of shown at once.
    var async = false
}

enum CodexQuestionWatcher {
    /// Unanswered questions in recently active Codex transcripts, newest file first.
    static func scan() -> [CodexQuestion] {
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

    private static func pending(in url: URL) -> CodexQuestion? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 1_500_000
        try? handle.seek(toOffset: size > window ? size - window : 0)
        guard let data = try? handle.readToEnd() else { return nil }

        var calls: [(id: String, items: [CodexQuestion.Item], async: Bool)] = []
        var answered = Set<String>()
        for line in data.split(separator: 0x0A) {
            // async questions get an instant {"accepted":true} output; the real answer
            // arrives later as a user message quoting the call id
            if line.range(of: Data("send_user_message_question_reply".utf8)) != nil {
                let text = String(decoding: line, as: UTF8.self)
                for m in text.matches(of: /call_[A-Za-z0-9]+/) { answered.insert(String(m.output)) }
                continue
            }
            let isCall = line.range(of: Data("request_user_input".utf8)) != nil
            let isOut = line.range(of: Data("function_call_output".utf8)) != nil
            guard isCall || isOut,
                  let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let p = obj["payload"] as? [String: Any], let callID = p["call_id"] as? String else { continue }
            if p["type"] as? String == "function_call_output" {
                if !calls.contains(where: { $0.id == callID && $0.async }) { answered.insert(callID) }
                continue
            }
            guard (p["name"] as? String)?.hasPrefix("request_user_input") == true,
                  let args = (p["arguments"] as? String)?.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: args) as? [String: Any],
                  let qs = parsed["questions"] as? [[String: Any]] else { continue }
            let items = qs.compactMap { q -> CodexQuestion.Item? in
                guard let title = (q["title"] as? String) ?? (q["question"] as? String) else { return nil }
                let opts = (q["options"] as? [String]) ?? (q["options"] as? [[String: Any]])?.compactMap { $0["label"] as? String } ?? []
                return .init(title: title, options: opts)
            }
            if !items.isEmpty { calls.append((callID, items, p["name"] as? String == "request_user_input_async")) }
        }
        guard let last = calls.last(where: { !answered.contains($0.id) }), let cwd = cwd(of: url) else { return nil }
        return CodexQuestion(id: last.id, cwd: cwd, items: last.items, async: last.async)
    }

    private static func cwd(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url), let head = try? handle.read(upToCount: 131_072) else { return nil }
        try? handle.close()
        guard let line = head.split(separator: 0x0A).first,
              let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { return nil }
        return (obj["payload"] as? [String: Any])?["cwd"] as? String
    }
}
