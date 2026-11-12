import Foundation

/// Read-only fallback for Codex clients that do not emit CLI hooks. Reads only
/// recent rollouts, then consumes appended complete JSONL records on each poll.
public actor CodexActivityReader {
    public struct Snapshot: Sendable {
        public var inbound: VNInbound
        public var updatedAt: Date
    }

    private struct Progress {
        var offset: UInt64 = 0
        var skippingOversizedRecord = false
        var snapshot: Snapshot?
    }
    private var progress: [URL: Progress] = [:]
    private let root: URL

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")) {
        self.root = root
    }

    public func scan(now: Date = Date()) -> [Snapshot] {
        let fm = FileManager.default
        let cutoff = now.addingTimeInterval(-1800)
        guard let files = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                        options: [.skipsHiddenFiles]) else { return [] }
        let recent = files.compactMap { item -> (URL, Date)? in
            guard let url = item as? URL, url.pathExtension == "jsonl",
                  let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  date > cutoff else { return nil }
            return (url, date)
        }.sorted { $0.1 > $1.1 }.prefix(32).map(\.0)
        progress = progress.filter { recent.contains($0.key) }
        for url in recent {
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            var state = progress[url] ?? Progress()
            if size < state.offset { state = Progress() }
            // Bound initial work even for multi-gigabyte sessions: metadata is
            // at the start, while current activity is at the end.
            if state.offset == 0 && size > 4_194_304 {
                try? handle.seek(toOffset: 0)
                if let head = try? handle.read(upToCount: 262_144) { consume(head, state: &state) }
                state.offset = size - 524_288
                try? handle.seek(toOffset: state.offset)
                if let tail = try? handle.read(upToCount: 524_288), let first = tail.firstIndex(of: 10) {
                    state.offset += UInt64(first + 1)
                }
            }
            try? handle.seek(toOffset: state.offset)
            if var data = try? handle.read(upToCount: 4_194_304) {
                if state.skippingOversizedRecord {
                    if let first = data.firstIndex(of: 10) {
                        state.offset += UInt64(first + 1)
                        data = Data(data.dropFirst(first + 1))
                        state.skippingOversizedRecord = false
                    } else {
                        state.offset += UInt64(data.count)
                        data = Data()
                    }
                }
                if let last = data.lastIndex(of: 10) {
                    consume(Data(data[...last]), state: &state)
                    state.offset += UInt64(last + 1)
                } else if data.count == 4_194_304 {
                    // A single enormous output must not stall all later events.
                    state.offset += UInt64(data.count)
                    state.skippingOversizedRecord = true
                }
            }
            progress[url] = state
        }
        return progress.values.compactMap(\.snapshot).filter { $0.updatedAt > cutoff }
    }

    private func consume(_ data: Data, state: inout Progress) {
        for line in data.split(separator: 10) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  let timestamp = obj["timestamp"] as? String,
                  let date = Self.date(timestamp) else { continue }
            if obj["type"] as? String == "session_meta" {
                guard let id = payload["id"] as? String, let cwd = payload["cwd"] as? String else { continue }
                state.snapshot = Snapshot(inbound: VNInbound(type: .notify, source: "codex", event: "SessionStart",
                                                              cwd: cwd, sessionId: id), updatedAt: date)
                continue
            }
            guard var snapshot = state.snapshot else { continue }
            let kind = payload["type"] as? String
            if obj["type"] as? String == "event_msg" {
                switch kind {
                case "task_started":
                    snapshot.inbound.event = "UserPromptSubmit"
                    snapshot.inbound.tool = nil
                    snapshot.inbound.detail = nil
                case "task_complete", "turn_aborted":
                    // An interrupted turn is not a successful completion. Keep
                    // that distinction before projecting a user-facing phase.
                    snapshot.inbound.event = kind == "turn_aborted" ? "Interrupted" : "Stop"
                    snapshot.inbound.tool = nil
                    snapshot.inbound.detail = (payload["last_agent_message"] as? String).map { String($0.prefix(500)) }
                default: continue
                }
            } else if obj["type"] as? String == "response_item" {
                switch kind {
                case "function_call", "custom_tool_call":
                    snapshot.inbound.event = "PreToolUse"
                    snapshot.inbound.tool = payload["name"] as? String
                    // Tool inputs can contain entire files or internal metadata;
                    // the tool name is enough to show useful live activity.
                    snapshot.inbound.detail = nil
                case "message":
                    guard payload["role"] as? String == "user",
                          let content = payload["content"] as? [[String: Any]],
                          let text = content.compactMap({ $0["text"] as? String }).last,
                          !text.hasPrefix("<environment_context>"), !text.hasPrefix("<codex_internal_context"),
                          !text.hasPrefix("# AGENTS.md") else { continue }
                    let message = text.replacingOccurrences(of: #"</?image\b[^>]*>|\[Image #\d+\]"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    snapshot.inbound.userMessage = String(message.prefix(300))
                default: continue
                }
            } else { continue }
            snapshot.updatedAt = date
            state.snapshot = snapshot
        }
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
