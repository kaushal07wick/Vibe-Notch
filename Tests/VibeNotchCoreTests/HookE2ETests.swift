import XCTest
@testable import VibeNotchCore

/// End-to-end: run the real `vibenotch-hook` binary against an in-test IPC
/// server and assert the exact JSON it prints to the agent.
final class HookE2ETests: XCTestCase {

    /// The built hook binary sits next to the test bundle in the products dir.
    private var hookBinary: URL {
        Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("vibenotch-hook")
    }

    private func runHook(stdin: String, socketPath: String) throws -> String {
        let p = Process()
        p.executableURL = hookBinary
        p.arguments = ["--source", "claude"]
        p.environment = ProcessInfo.processInfo.environment
            .merging(["VIBENOTCH_SOCKET": socketPath]) { _, new in new }
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        try p.run()
        inPipe.fileHandleForWriting.write(stdin.data(using: .utf8)!)
        inPipe.fileHandleForWriting.closeFile()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: out, encoding: .utf8) ?? ""
    }

    func testPermissionRequestAllowEndToEnd() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: hookBinary.path))
        let sock = NSTemporaryDirectory() + "e2e-\(UUID().uuidString.prefix(8)).sock"
        let server = IPCServer(socketPath: sock,
                               onNotify: { _ in },
                               onRequest: { _, inbound, complete in
                                   XCTAssertEqual(inbound.tool, "Bash")
                                   XCTAssertEqual(inbound.detail, "echo hi")
                                   complete(VNReply(decision: .allow))
                               })
        try server.start()
        defer { server.stop() }

        let out = try runHook(stdin: #"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"echo hi"},"session_id":"e2e"}"#,
                              socketPath: sock)
        XCTAssertTrue(out.contains(#""behavior":"allow""#), "got: \(out)")
    }

    func testPermissionRequestFailOpenWhenServerAbsent() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: hookBinary.path))
        let out = try runHook(stdin: #"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"x"},"session_id":"e2e"}"#,
                              socketPath: NSTemporaryDirectory() + "missing.sock")
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "",
                       "no server → no output → agent's own flow decides")
    }

    func testQuestionAnswersRideUpdatedInput() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: hookBinary.path))
        let sock = NSTemporaryDirectory() + "e2e-\(UUID().uuidString.prefix(8)).sock"
        let server = IPCServer(socketPath: sock,
                               onNotify: { _ in },
                               onRequest: { _, inbound, complete in
                                   XCTAssertEqual(inbound.questions?.first?.options.count, 2)
                                   complete(VNReply(decision: .allow, answers: ["Option B"]))
                               })
        try server.start()
        defer { server.stop() }

        let stdin = #"{"hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","header":"Choice","options":[{"label":"Option A"},{"label":"Option B"}]}]},"session_id":"e2e"}"#
        let out = try runHook(stdin: stdin, socketPath: sock)
        XCTAssertTrue(out.contains(#""behavior":"allow""#), "got: \(out)")
        XCTAssertTrue(out.contains("Option B"), "answers must ride updatedInput: \(out)")
    }
}

extension HookE2ETests {
    func testCodexPermissionRequestUsesCodexEnvelope() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: hookBinaryPathForExtension))
        let sock = NSTemporaryDirectory() + "e2e-\(UUID().uuidString.prefix(8)).sock"
        let server = IPCServer(socketPath: sock,
                               onNotify: { _ in },
                               onRequest: { _, inbound, complete in
                                   XCTAssertEqual(inbound.source, "codex")
                                   complete(VNReply(decision: .allow))
                               })
        try server.start()
        defer { server.stop() }

        let out = try runHookForExtension(
            source: "codex",
            stdin: #"{"hook_event_name":"PermissionRequest","tool_name":"Shell","tool_input":{"command":"ls"},"session_id":"cx"}"#,
            socketPath: sock)
        XCTAssertTrue(out.contains(#""continue":true"#), "codex envelope required: \(out)")
        XCTAssertTrue(out.contains(#""behavior":"allow""#), "got: \(out)")
    }

    // extension-visible helpers (private members aren't accessible here)
    var hookBinaryPathForExtension: String {
        Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("vibenotch-hook").path
    }

    func runHookForExtension(source: String, stdin: String, socketPath: String) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: hookBinaryPathForExtension)
        p.arguments = ["--source", source]
        p.environment = ProcessInfo.processInfo.environment
            .merging(["VIBENOTCH_SOCKET": socketPath]) { _, new in new }
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        try p.run()
        inPipe.fileHandleForWriting.write(stdin.data(using: .utf8)!)
        inPipe.fileHandleForWriting.closeFile()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: out, encoding: .utf8) ?? ""
    }
}
