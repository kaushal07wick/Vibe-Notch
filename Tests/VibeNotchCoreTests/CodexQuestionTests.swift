import XCTest
@testable import VibeNotchCore

final class CodexQuestionTests: XCTestCase {
    private let session = "00000000-0000-0000-0000-000000000001"

    private func transcript(_ payloads: [[String: Any]]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("rollout-2026-11-12T12-00-00-\(session).jsonl")
        let metadata: [String: Any] = ["type": "session_meta", "payload": ["id": session, "cwd": "/tmp/shared-folder"]]
        let records: [[String: Any]] = [metadata] + payloads.map { ["type": "response_item", "payload": $0] }
        let lines = try records.map { try JSONSerialization.data(withJSONObject: $0) + Data([10]) }
        try lines.reduce(Data(), +).write(to: url)
        return url
    }

    private func call(async: Bool = true) throws -> [String: Any] {
        let args = try JSONSerialization.data(withJSONObject: ["questions": [
            ["title": "Pick one", "options": ["One", "Two"]],
            ["title": "Describe it"],
        ]])
        return ["type": "function_call", "name": async ? "request_user_input_async" : "request_user_input",
                "call_id": "call_test", "arguments": String(decoding: args, as: UTF8.self)]
    }

    private func decodeReply(_ text: String) throws -> [[String: Any]] {
        let json = text.replacingOccurrences(of: "<send_user_message_question_reply>", with: "")
            .replacingOccurrences(of: "</send_user_message_question_reply>", with: "")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
    }

    func testAsyncAnswersUseExactSessionQuestionAndText() throws {
        let url = try transcript([call(), ["type": "function_call_output", "call_id": "call_test", "output": "{\"accepted\":true}"]])
        let question = try XCTUnwrap(CodexQuestionWatcher.pending(in: url))
        XCTAssertEqual(question.sessionID, session)
        let choice = try decodeReply(XCTUnwrap(question.reply(step: 0, option: 1, text: nil)))
        XCTAssertEqual(choice.first?["answer"] as? String, "Two")
        XCTAssertEqual(choice.first?["questionItemId"] as? String, #"["request_user_input_async","call_test",0]"#)
        let text = "हैलो \"quoted\"\nline two 🚀"
        let reply = try XCTUnwrap(question.reply(step: 1, option: 0, text: text))
        XCTAssertEqual(try decodeReply(reply).first?["answer"] as? String, text)
        XCTAssertNil(question.reply(step: 1, option: 0, text: " \n "))
        XCTAssertNil(question.reply(step: 1, option: 1, text: text))
        XCTAssertNil(question.reply(step: 2, option: 0, text: text))
    }

    func testPartialRepliesKeepRemainingQuestionWithOriginalIndex() throws {
        let url = try transcript([call()])
        let question = try XCTUnwrap(CodexQuestionWatcher.pending(in: url))
        let reply = try XCTUnwrap(question.reply(step: 0, option: 0, text: nil))
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        func append(_ payload: [String: Any]) throws {
            try handle.write(contentsOf: JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": payload]) + Data([10]))
        }
        // A tool mentioning a reply must not dismiss the real user's question.
        try append(["type": "function_call_output", "call_id": "call_other", "output": reply])
        XCTAssertEqual(CodexQuestionWatcher.pending(in: url)?.items.count, 2)
        try append(["type": "message", "role": "user", "content": [["type": "input_text", "text": reply]]])
        let remaining = try XCTUnwrap(CodexQuestionWatcher.pending(in: url))
        XCTAssertEqual(remaining.items.count, 1)
        XCTAssertEqual(remaining.items.first?.index, 1)
        let lastReply = try XCTUnwrap(remaining.reply(step: 0, option: 0, text: "answer"))
        XCTAssertEqual(try decodeReply(lastReply).first?["questionItemId"] as? String,
                       #"["request_user_input_async","call_test",1]"#)
        try append(["type": "message", "role": "user", "content": [["text": lastReply]]])
        XCTAssertNil(CodexQuestionWatcher.pending(in: url))
    }

    func testSynchronousToolOutputDismissesQuestion() throws {
        let url = try transcript([call(async: false), ["type": "function_call_output", "call_id": "call_test", "output": "{}"]])
        XCTAssertNil(CodexQuestionWatcher.pending(in: url))
    }

    func testNumericChoiceDoesNotSubmitEnter() {
        let tmux = InjectionPlan.make(terminal: "Ghostty", tty: nil,
            meta: ["TMUX": "/tmp/test,1,0", "TMUX_PANE": "%1"], text: "2", submit: false)
        XCTAssertEqual(tmux.commands.count, 1)
        XCTAssertEqual(tmux.commands.first?.last, "2")
        let wezterm = InjectionPlan.make(terminal: "WezTerm", tty: nil,
            meta: ["WEZTERM_PANE": "1"], text: "2", submit: false)
        XCTAssertEqual(wezterm.commands.first?.last, "2")
        let iterm = InjectionPlan.make(terminal: "iTerm", tty: "ttys003", meta: [:], text: "2", submit: false)
        XCTAssertTrue(iterm.appleScript?.contains("newline NO") == true)
        XCTAssertFalse(InjectionPlan.make(terminal: "Terminal", tty: "ttys003", meta: [:], text: "2", submit: false).isSupported)
    }
}
