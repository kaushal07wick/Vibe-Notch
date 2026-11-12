import Foundation

public struct CodexPendingQuestion: Equatable, Identifiable, Sendable {
    public struct Item: Equatable, Sendable {
        public let title: String
        public let options: [String]
        public let index: Int
        public init(title: String, options: [String], index: Int = 0) {
            self.title = title; self.options = options; self.index = index
        }
    }
    public let id: String
    public let sessionID: String
    public let cwd: String
    public let items: [Item]
    public let async: Bool

    public init(id: String, sessionID: String, cwd: String, items: [Item], async: Bool = false) {
        self.id = id; self.sessionID = sessionID; self.cwd = cwd; self.items = items; self.async = async
    }

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

/// Reduces complete transcript records in order. An async acknowledgement is
/// not an answer, but a new user turn supersedes questions from the old turn.
public enum CodexQuestionParser {
    private struct Pending {
        let question: CodexPendingQuestion
        let rootTurn: String?
        let turn: String?
    }

    public static func pending(in data: Data, sessionID: String, cwd: String) -> CodexPendingQuestion? {
        guard !sessionID.isEmpty, !cwd.isEmpty, let lastNewline = data.lastIndex(of: 10) else { return nil }
        var calls: [Pending] = []
        var rootTurn: String?
        var turn: String?
        let records = data[...lastNewline].split(separator: 10).compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0))) as? [String: Any]
        }
        var replyCallsForNextTurn = Set<String>()
        for (offset, record) in records.enumerated() {
            guard let payload = record["payload"] as? [String: Any] else { continue }
            if let text = userText(in: record) {
                if let targets = replyTargets(in: text) {
                    applyReplies(targets, calls: &calls)
                    replyCallsForNextTurn = Set(targets.map(\.callID)).intersection(calls.map { $0.question.id })
                } else {
                    calls.removeAll()
                    replyCallsForNextTurn.removeAll()
                }
                continue
            }
            let kind = payload["type"] as? String
            let recordType = record["type"] as? String
            if recordType == "event_msg" {
                let attribution = payload["turn_attribution"] as? [String: Any]
                let nextTurn = payload["turn_id"] as? String
                let nextRoot = (payload["root_turn_id"] as? String) ?? (attribution?["root_turn_id"] as? String) ?? nextTurn
                switch kind {
                case "task_started":
                    // Automatic continuation of the same root turn may retain an
                    // async question. A new root or missing identity cannot.
                    // A delivered question reply starts a new daemon turn. Keep
                    // its remaining items while still expiring unrelated roots.
                    let replies = replyCallsForNextTurn.union(replyCalls(after: offset, in: records))
                    calls = calls.compactMap { call in
                        let replying = call.question.async && replies.contains(call.question.id)
                        guard replying || (nextRoot != nil && call.rootTurn == nextRoot) else { return nil }
                        return replying ? Pending(question: call.question, rootTurn: nextRoot, turn: nextTurn) : call
                    }
                    replyCallsForNextTurn.removeAll()
                    rootTurn = nextRoot; turn = nextTurn
                case "turn_aborted":
                    calls.removeAll { nextTurn == nil || $0.turn == nil || $0.turn == nextTurn }
                case "task_complete":
                    replyCallsForNextTurn.removeAll()
                    calls.removeAll { !$0.question.async && (nextTurn == nil || $0.turn == nil || $0.turn == nextTurn) }
                default: break
                }
                continue
            }
            guard recordType == "response_item" else { continue }
            guard let callID = payload["call_id"] as? String else { continue }
            if kind == "function_call_output" || kind == "custom_tool_call_output" {
                let output = payload["output"] as? String ?? ""
                let reply = output.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let acknowledged = reply?["accepted"] as? Bool == true && reply?["answers"] == nil && reply?["error"] == nil
                calls.removeAll { $0.question.id == callID && (!$0.question.async || !acknowledged) }
                continue
            }
            guard kind == "function_call" || kind == "custom_tool_call",
                  let name = (payload["name"] as? String)?.split(separator: ".").last.map(String.init),
                  name == "request_user_input" || name == "request_user_input_async",
                  let arguments = (payload["arguments"] as? String ?? payload["input"] as? String)?.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: arguments) as? [String: Any],
                  let questions = parsed["questions"] as? [[String: Any]] else { continue }
            let items = questions.enumerated().compactMap { index, item -> CodexPendingQuestion.Item? in
                guard let title = item["title"] as? String ?? item["question"] as? String else { return nil }
                let options = item["options"] as? [String] ?? (item["options"] as? [[String: Any]])?.compactMap { $0["label"] as? String } ?? []
                return .init(title: title, options: options, index: index)
            }
            guard !items.isEmpty else { continue }
            let metadata = payload["internal_chat_message_metadata_passthrough"] as? [String: Any]
            let callTurn = (metadata?["turn_id"] as? String) ?? turn
            let question = CodexPendingQuestion(id: callID, sessionID: sessionID, cwd: cwd, items: items,
                                               async: name == "request_user_input_async")
            calls.removeAll { $0.question.id == callID }
            calls.append(Pending(question: question, rootTurn: rootTurn ?? callTurn, turn: callTurn))
        }
        return calls.last?.question
    }

    private struct ReplyTarget {
        let callID: String
        let index: Int?
    }

    private static func userText(in record: [String: Any]) -> String? {
        guard let payload = record["payload"] as? [String: Any] else { return nil }
        let text: String
        if record["type"] as? String == "event_msg", payload["type"] as? String == "user_message" {
            text = payload["message"] as? String ?? payload["text"] as? String ?? ""
        } else if record["type"] as? String == "response_item", payload["type"] as? String == "message",
                  payload["role"] as? String == "user" {
            text = (payload["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
        } else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("<environment_context>"),
              !trimmed.hasPrefix("<codex_internal_context"), !trimmed.hasPrefix("# AGENTS.md") else { return nil }
        return trimmed
    }

    private static func replyTargets(in text: String) -> [ReplyTarget]? {
        guard text.contains("send_user_message_question_reply") else { return nil }
        if let start = text.range(of: "<send_user_message_question_reply>"),
           let end = text.range(of: "</send_user_message_question_reply>"), start.upperBound <= end.lowerBound,
           let data = String(text[start.upperBound..<end.lowerBound]).data(using: .utf8),
           let value = try? JSONSerialization.jsonObject(with: data) {
            let replies = value as? [[String: Any]] ?? (value as? [String: Any]).map { [$0] } ?? []
            return replies.compactMap { reply in
                guard let id = reply["questionItemId"] as? String else { return nil }
                if let keyData = id.data(using: .utf8),
                   let key = (try? JSONSerialization.jsonObject(with: keyData)) as? [Any],
                   key.count == 3, key[0] as? String == "request_user_input_async",
                   let callID = key[1] as? String, let index = key[2] as? Int, index >= 0 {
                    return ReplyTarget(callID: callID, index: index)
                }
                guard id.range(of: "^call_[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
                return ReplyTarget(callID: id, index: nil)
            }
        }
        // Retain compatibility with older plain-text reply markers, but never
        // treat an invalid structured payload as a reply to every mentioned ID.
        guard !text.contains("<send_user_message_question_reply>") else { return [] }
        return text.matches(of: /call_[A-Za-z0-9_-]+/).map { ReplyTarget(callID: String($0.output), index: nil) }
    }

    private static func applyReplies(_ targets: [ReplyTarget], calls: inout [Pending]) {
        calls = calls.compactMap { call in
            let matching = targets.filter { $0.callID == call.question.id }
            guard !matching.contains(where: { $0.index == nil }) else { return nil }
            let answered = Set(matching.compactMap(\.index))
            let question = call.question
            let remaining = question.items.filter { !answered.contains($0.index) }
            guard !remaining.isEmpty else { return nil }
            return Pending(question: CodexPendingQuestion(id: question.id, sessionID: question.sessionID,
                cwd: question.cwd, items: remaining, async: question.async), rootTurn: call.rootTurn, turn: call.turn)
        }
    }

    private static func replyCalls(after offset: Int, in records: [[String: Any]]) -> Set<String> {
        for record in records.dropFirst(offset + 1) {
            if record["type"] as? String == "event_msg",
               (record["payload"] as? [String: Any])?["type"] as? String == "task_started" { break }
            if let text = userText(in: record) {
                return Set(replyTargets(in: text)?.map(\.callID) ?? [])
            }
        }
        return []
    }
}
