import XCTest
@testable import VibeNotchCore

final class CodexActivityReaderTests: XCTestCase {
    func testDiscoversExistingSessionAndTracksAppendedRecordsWithoutDuplicates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("rollout.jsonl")
        let now = Date()
        let start = try record("session_meta", ["id": "session-1", "cwd": "/tmp/project", "source": "vscode"], at: now)
        let task = try record("event_msg", ["type": "task_started"], at: now)
        let user = try record("response_item", ["type": "message", "role": "user", "content": [["type": "input_text", "text": "Fix the layout"]]], at: now)
        try (start + task + user).write(to: file)
        let reader = CodexActivityReader(root: root)
        let first = await reader.scan(now: now)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.inbound.sessionId, "session-1")
        XCTAssertEqual(first.first?.inbound.cwd, "/tmp/project")
        XCTAssertEqual(first.first?.inbound.event, "UserPromptSubmit")
        XCTAssertEqual(first.first?.inbound.userMessage, "Fix the layout")
        let tool = try record("response_item", ["type": "custom_tool_call", "name": "functions.exec", "input": "private input"], at: now.addingTimeInterval(1))
        let writer = try FileHandle(forWritingTo: file)
        defer { try? writer.close() }
        try writer.seekToEnd()
        // Incomplete JSONL writes must not advance the cursor or lose the event.
        try writer.write(contentsOf: tool.dropLast())
        let partial = await reader.scan(now: now.addingTimeInterval(1))
        XCTAssertEqual(partial.first?.inbound.event, "UserPromptSubmit")
        try writer.write(contentsOf: Data([10]))
        let running = await reader.scan(now: now.addingTimeInterval(1))
        XCTAssertEqual(running.first?.inbound.tool, "functions.exec")
        XCTAssertEqual(running.first?.inbound.event, "PreToolUse")
        XCTAssertNil(running.first?.inbound.detail)
        let unchanged = await reader.scan(now: now.addingTimeInterval(2))
        XCTAssertEqual(unchanged.count, 1)
        XCTAssertEqual(unchanged.first?.updatedAt, running.first?.updatedAt)
        try writer.write(contentsOf: record("event_msg", ["type": "task_complete", "last_agent_message": "Done"], at: now.addingTimeInterval(3)))
        let completed = await reader.scan(now: now.addingTimeInterval(3))
        XCTAssertEqual(completed.first?.inbound.event, "Stop")
        XCTAssertNil(completed.first?.inbound.tool)
        XCTAssertEqual(completed.first?.inbound.detail, "Done")
        let expired = await reader.scan(now: now.addingTimeInterval(1900))
        XCTAssertTrue(expired.isEmpty)
    }

    func testMalformedRecordsTruncationAndMissingDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let reader = CodexActivityReader(root: root)
        let missing = await reader.scan()
        XCTAssertTrue(missing.isEmpty)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("rollout.jsonl")
        let now = Date()
        var contents = try record("session_meta", ["id": "old", "cwd": "/tmp/old"], at: now)
        contents.append(Data("broken record\n".utf8))
        contents.append(try record("event_msg", ["type": "turn_aborted"], at: now))
        try contents.write(to: file)
        let aborted = await reader.scan(now: now)
        XCTAssertEqual(aborted.first?.inbound.event, "Interrupted")
        XCTAssertEqual(aborted.first.map { SessionPhase.resolve(event: $0.inbound.event, updatedAt: $0.updatedAt, now: now) }, .interrupted)
        try record("session_meta", ["id": "new", "cwd": "/tmp/new"], at: now).write(to: file)
        let reset = await reader.scan(now: now)
        XCTAssertEqual(reset.first?.inbound.sessionId, "new")
        XCTAssertEqual(reset.first.map { SessionPhase.resolve(event: $0.inbound.event, updatedAt: $0.updatedAt, now: now) }, .unknown)
    }

    func testLargeToolOutputDoesNotStallLaterActivity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("rollout.jsonl")
        let now = Date()
        try record("session_meta", ["id": "large", "cwd": "/tmp/project"], at: now).write(to: file)
        let reader = CodexActivityReader(root: root)
        _ = await reader.scan(now: now)
        let writer = try FileHandle(forWritingTo: file)
        defer { try? writer.close() }
        try writer.seekToEnd()
        try writer.write(contentsOf: Data(repeating: 120, count: 5_000_000))
        try writer.write(contentsOf: Data([10]))
        try writer.write(contentsOf: record("event_msg", ["type": "task_complete"], at: now))
        _ = await reader.scan(now: now)
        let finished = await reader.scan(now: now)
        XCTAssertEqual(finished.first?.inbound.event, "Stop")
    }

    private func record(_ type: String, _ payload: [String: Any], at date: Date) throws -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var data = try JSONSerialization.data(withJSONObject: ["type": type, "timestamp": formatter.string(from: date), "payload": payload])
        data.append(10)
        return data
    }
}
