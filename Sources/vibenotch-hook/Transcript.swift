import Foundation

// Bounded transcript access + extractors.

/// Bounded transcript view: the head (first user prompt lives there) and the
/// tail (latest messages). One read total instead of four full-file passes —
/// this was the approval-card latency on long sessions.
struct Transcript {
    let headLines: [String]
    let tailLines: [String]

    init?(_ path: String?) {
        guard let path, let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0

        try? fh.seek(toOffset: 0)
        let headData = fh.readData(ofLength: 64 * 1024)
        var head = String(decoding: headData, as: UTF8.self).components(separatedBy: "\n")
        if UInt64(headData.count) < size { head.removeLast() } // drop partial line
        headLines = head

        let tailCap: UInt64 = 256 * 1024
        let offset = size > tailCap ? size - tailCap : 0
        try? fh.seek(toOffset: offset)
        var tail = String(decoding: fh.readDataToEndOfFile(), as: UTF8.self).components(separatedBy: "\n")
        if offset > 0, !tail.isEmpty { tail.removeFirst() } // drop partial line
        tailLines = tail
    }

    static func parse(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// Text of the last assistant message in a Claude Code transcript (JSONL).
func lastAssistantText(_ t: Transcript?) -> String? {
    for line in (t?.tailLines ?? []).reversed() {
        guard let obj = Transcript.parse(line) else { continue }
        let msg = (obj["message"] as? [String: Any]) ?? obj
        let role = (msg["role"] as? String) ?? (obj["type"] as? String)
        guard role == "assistant" else { continue }
        if let text = extractText(msg["content"]) ?? extractText(obj["content"]), !text.isEmpty {
            return text
        }
    }
    return nil
}

/// The model id from the last assistant message, mapped to a friendly name.
func lastAssistantModel(_ t: Transcript?) -> String? {
    for line in (t?.tailLines ?? []).reversed() {
        guard let obj = Transcript.parse(line) else { continue }
        let msg = (obj["message"] as? [String: Any]) ?? obj
        guard (msg["role"] as? String) == "assistant", let id = msg["model"] as? String else { continue }
        return friendlyModel(id)
    }
    return nil
}

func friendlyModel(_ id: String) -> String {
    let parts = id.lowercased().split(separator: "-").map(String.init)
    let families = ["opus": "Opus", "sonnet": "Sonnet", "haiku": "Haiku", "fable": "Fable"]
    guard let idx = parts.firstIndex(where: { families[$0] != nil }) else { return id }
    let family = families[parts[idx]]!
    let nums = parts[(idx + 1)...].prefix(while: { Int($0) != nil }).prefix(2)
    return nums.isEmpty ? family : "\(family) \(nums.joined(separator: "."))"
}

func extractText(_ content: Any?) -> String? {
    if let s = content as? String { return s }
    if let parts = content as? [[String: Any]] {
        let texts = parts.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }
    return nil
}

/// First (task) or last user message, skipping tool-result/system noise.
func userText(_ t: Transcript?, first: Bool) -> String? {
    let lines = first ? (t?.headLines ?? []) : (t?.tailLines ?? []).reversed().map { $0 }
    for line in lines {
        guard let obj = Transcript.parse(line) else { continue }
        let msg = (obj["message"] as? [String: Any]) ?? obj
        let role = (msg["role"] as? String) ?? (obj["type"] as? String)
        guard role == "user", let text = extractText(msg["content"]) ?? extractText(obj["content"]) else { continue }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty || clean.hasPrefix("<") { continue } // skip system-reminder / tool blocks
        return clean
    }
    return nil
}

/// Token usage of the newest assistant message in the tail.
func latestUsage(_ t: Transcript?) -> (input: Int?, output: Int?) {
    for line in (t?.tailLines ?? []).reversed() {
        guard let obj = Transcript.parse(line),
              let msg = obj["message"] as? [String: Any],
              (msg["role"] as? String) == "assistant",
              let usage = msg["usage"] as? [String: Any] else { continue }
        return (usage["input_tokens"] as? Int, usage["output_tokens"] as? Int)
    }
    return (nil, nil)
}
