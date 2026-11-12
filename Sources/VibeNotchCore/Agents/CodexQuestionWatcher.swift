import Foundation

/// Codex asks its multiple-choice questions inside its own TUI and fires no hook for them,
/// but every ask lands in the session transcript. Sync calls wait for a tool output;
/// async calls get an immediate acknowledgment and later receive per-question user replies.
public struct CodexQuestion: Equatable, Identifiable, Sendable {
    public struct Item: Equatable, Sendable {
        public let title: String
        public let options: [String]
        public let index: Int
    }
    public let id: String          // call_id
    public let sessionID: String
    public let cwd: String
    public let items: [Item]
    public var async = false

    public func reply(step: Int, option: Int, text: String?) -> String? {
        guard items.indices.contains(step) else { return nil }
        let item = items[step]
        let answer: String
        if option == item.options.count, let text {
            answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if item.options.indices.contains(option), text == nil {
            answer = item.options[option]
        } else { return nil }
        guard !answer.isEmpty, !answer.contains("\0"),
              let key = try? JSONSerialization.data(withJSONObject: ["request_user_input_async", id, item.index]),
              let keyString = String(data: key, encoding: .utf8),
              let data = try? JSONSerialization.data(withJSONObject: [[
                "questionItemId": keyString, "question": item.title, "answer": answer,
              ]]), let json = String(data: data, encoding: .utf8) else { return nil }
        return "<send_user_message_question_reply>\n\(json)\n</send_user_message_question_reply>"
    }
}

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

        var calls: [(id: String, items: [CodexQuestion.Item], async: Bool)] = []
        var answered = Set<String>()
        var answeredItems = Set<String>()
        for line in data.split(separator: 0x0A) {
            // async questions get an instant {"accepted":true} output; the real answer
            // arrives later as a user message quoting the call id
            if line.range(of: Data("send_user_message_question_reply".utf8)) != nil,
               let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
               let p = obj["payload"] as? [String: Any], p["type"] as? String == "message",
               p["role"] as? String == "user", let content = p["content"] as? [[String: Any]] {
                for part in content {
                    guard let text = part["text"] as? String,
                          let start = text.range(of: "<send_user_message_question_reply>"),
                          let end = text.range(of: "</send_user_message_question_reply>"), start.upperBound <= end.lowerBound,
                          let data = String(text[start.upperBound..<end.lowerBound]).data(using: .utf8),
                          let parsed = try? JSONSerialization.jsonObject(with: data) else { continue }
                    let replies = (parsed as? [[String: Any]]) ?? (parsed as? [String: Any]).map { [$0] } ?? []
                    for reply in replies {
                        guard let id = reply["questionItemId"] as? String else { continue }
                        if let data = id.data(using: .utf8),
                           let key = try? JSONSerialization.jsonObject(with: data) as? [Any],
                           key.count == 3, let call = key[1] as? String, let index = key[2] as? Int {
                            answeredItems.insert("\(call):\(index)")
                        } else { answered.insert(id) }
                    }
                }
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
            let items = qs.enumerated().compactMap { index, q -> CodexQuestion.Item? in
                guard let title = (q["title"] as? String) ?? (q["question"] as? String) else { return nil }
                let opts = (q["options"] as? [String]) ?? (q["options"] as? [[String: Any]])?.compactMap { $0["label"] as? String } ?? []
                return .init(title: title, options: opts, index: index)
            }
            if !items.isEmpty { calls.append((callID, items, p["name"] as? String == "request_user_input_async")) }
        }
        guard let last = calls.last(where: { call in
            !answered.contains(call.id) && call.items.contains { !answeredItems.contains("\(call.id):\($0.index)") }
        }), let cwd = cwd(of: url) else { return nil }
        let items = last.items.filter { !answeredItems.contains("\(last.id):\($0.index)") }
        return CodexQuestion(id: last.id, sessionID: String(url.deletingPathExtension().lastPathComponent.suffix(36)),
                             cwd: cwd, items: items, async: last.async)
    }

    private static func cwd(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url), let head = try? handle.read(upToCount: 131_072) else { return nil }
        try? handle.close()
        guard let line = head.split(separator: 0x0A).first,
              let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { return nil }
        return (obj["payload"] as? [String: Any])?["cwd"] as? String
    }
}
