import XCTest
@testable import VibeNotchCore

final class CodexQuestionParserTests: XCTestCase {
    private let sid = "session-a"
    private func record(_ type: String, _ payload: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: ["type": type, "payload": payload])
        data.append(10); return data
    }
    private func start(_ turn: String, root: String? = nil) throws -> Data {
        try record("event_msg", ["type": "task_started", "turn_id": turn, "root_turn_id": root ?? turn])
    }
    private func ask(async: Bool = true, id: String = "call_question_with_suffix", qualified: Bool = false) throws -> Data {
        let args = try JSONSerialization.data(withJSONObject: ["questions": [["title": "Choose an option", "options": ["One", "Two"]]]])
        let name = (qualified ? "functions." : "") + (async ? "request_user_input_async" : "request_user_input")
        return try record("response_item", ["type": "function_call", "name": name, "call_id": id,
                                            "arguments": String(decoding: args, as: UTF8.self)])
    }
    private func pending(_ data: Data) -> CodexPendingQuestion? {
        CodexQuestionParser.pending(in: data, sessionID: sid, cwd: "/tmp/shared-project")
    }

    func testAsyncAcknowledgementAndTurnCompletionKeepCurrentQuestion() throws {
        var data = try start("turn-a") + ask()
        data += try record("response_item", ["type": "function_call_output", "call_id": "call_question_with_suffix", "output": "{\"accepted\":true}"])
        data += try record("event_msg", ["type": "task_complete", "turn_id": "turn-a"])
        XCTAssertEqual(pending(data)?.sessionID, sid)
        XCTAssertEqual(pending(data)?.async, true)
    }

    func testNewUserTurnExpiresOldAsyncQuestions() throws {
        var data = try start("turn-a") + ask()
        data += try record("event_msg", ["type": "task_complete", "turn_id": "turn-a"])
        data += try start("turn-b")
        XCTAssertNil(pending(data))
        data += try ask(id: "call_current")
        XCTAssertEqual(pending(data)?.id, "call_current")
    }

    func testSameRootContinuationPreservesQuestionAndAbortExpiresIt() throws {
        var data = try start("turn-a", root: "root-a") + ask()
        data += try start("continuation", root: "root-a")
        XCTAssertNotNil(pending(data))
        data += try record("event_msg", ["type": "turn_aborted", "turn_id": "turn-a"])
        XCTAssertNil(pending(data))
    }

    func testFreeTextFollowupExpiresQuestionButInjectedContextDoesNot() throws {
        var data = try start("turn-a") + ask()
        data += try record("response_item", ["type": "message", "role": "user", "content": [["text": "<environment_context>context</environment_context>"]]])
        XCTAssertNotNil(pending(data))
        data += try record("response_item", ["type": "message", "role": "user", "content": [["text": "Never mind, continue"]]])
        XCTAssertNil(pending(data))
    }

    func testExplicitReplyMatchesCompleteCallIDAndIgnoresToolOutputText() throws {
        var data = try start("turn-a") + ask(qualified: true)
        data += try record("response_item", ["type": "function_call_output", "call_id": "call_other", "output": "send_user_message_question_reply call_question_with_suffix"])
        XCTAssertNotNil(pending(data))
        data += try record("response_item", ["type": "message", "role": "user", "content": [["text": "send_user_message_question_reply call_question_with_suffix: One"]]])
        XCTAssertNil(pending(data))
    }

    func testSyncAnswersCompletionAndIncompleteRecords() throws {
        let data = try start("turn-a") + ask(async: false)
        let output = try record("response_item", ["type": "function_call_output", "call_id": "call_question_with_suffix", "output": "{\"answers\":{}}"])
        XCTAssertNotNil(pending(data + output.dropLast()))
        XCTAssertNil(pending(data + output))
        let completed = try record("event_msg", ["type": "task_complete", "turn_id": "turn-a"])
        XCTAssertNil(pending(data + completed))
    }
    private func askTwo() throws -> Data {
        let arguments = try JSONSerialization.data(withJSONObject: ["questions": [
            ["title": "First", "options": ["One", "Two"]],
            ["title": "Second", "options": ["Three", "Four"]]
        ]])
        return try record("response_item", ["type": "function_call", "name": "request_user_input_async",
            "call_id": "call_partial", "arguments": String(decoding: arguments, as: UTF8.self)])
    }

    private func itemReply(_ question: CodexPendingQuestion, step: Int = 0) throws -> Data {
        let reply = try XCTUnwrap(question.reply(step: step, option: 0, text: nil))
        return try record("response_item", ["type": "message", "role": "user", "content": [["text": reply]]])
    }

    func testPartialReplyKeepsOriginalIndexAcrossNewReplyTurn() throws {
        let original = try start("original") + askTwo()
        let question = try XCTUnwrap(pending(original))
        let userReply = try itemReply(question)
        for afterStart in [false, true] {
            let newTurn = try start("reply-turn")
            let data = original + (afterStart ? newTurn + userReply : userReply + newTurn)
            let remaining = try XCTUnwrap(pending(data))
            XCTAssertEqual(remaining.items.count, 1)
            XCTAssertEqual(remaining.items.first?.index, 1)
            XCTAssertEqual(remaining.items.first?.title, "Second")
            let duplicate = try XCTUnwrap(pending(data + userReply))
            XCTAssertEqual(duplicate.items.count, 1, "Duplicate transcript messages must not restore an answered item")
            XCTAssertNil(pending(data + (try itemReply(remaining))))
        }
    }

    func testPartialReplyStillExpiresWhenUserMovesOn() throws {
        let original = try start("original") + askTwo()
        let question = try XCTUnwrap(pending(original))
        let data = try original + start("reply-turn") + itemReply(question)
        XCTAssertNotNil(pending(data))
        let followup = try record("event_msg", ["type": "user_message", "message": "Never mind, work on something else"])
        XCTAssertNil(pending(data + followup))
        let complete = try record("event_msg", ["type": "task_complete", "turn_id": "reply-turn"])
        XCTAssertNil(pending(data + complete + (try start("unrelated"))))
    }

    func testMalformedReplyDoesNotDismissQuestion() throws {
        let data = try start("original") + askTwo()
        let malformed = try record("response_item", ["type": "message", "role": "user", "content": [[
            "text": "<send_user_message_question_reply>invalid call_partial</send_user_message_question_reply>"
        ]]])
        XCTAssertEqual(pending(data + malformed)?.items.count, 2)
    }

}
