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
        let sock = "/tmp/e2e-\(UUID().uuidString.prefix(8)).sock"
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
                              socketPath: "/tmp/vn-missing.sock")
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "",
                       "no server → no output → agent's own flow decides")
    }

    func testQuestionAnswersRideUpdatedInput() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: hookBinary.path))
        let sock = "/tmp/e2e-\(UUID().uuidString.prefix(8)).sock"
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
        let sock = "/tmp/e2e-\(UUID().uuidString.prefix(8)).sock"
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

extension HookE2ETests {
    /// The remote Python client speaks the same protocol — run it for real.
    func testRemotePythonClientPermissionFlow() throws {
        let client = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/vibenotch-remote-hook.py")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: client.path))

        let sock = "/tmp/e2e-py-\(UUID().uuidString.prefix(8)).sock"
        let server = IPCServer(socketPath: sock,
                               onNotify: { _ in },
                               onRequest: { _, inbound, complete in
                                   XCTAssertNotNil(inbound.host, "remote events must carry a host")
                                   XCTAssertTrue(inbound.sessionId?.contains(":") == true,
                                                 "session ids are host-prefixed")
                                   complete(VNReply(decision: .deny))
                               })
        try server.start()
        defer { server.stop() }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = [client.path, "--source", "claude"]
        p.environment = ProcessInfo.processInfo.environment
            .merging(["VIBENOTCH_SOCKET": sock]) { _, new in new }
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        try p.run()
        inPipe.fileHandleForWriting.write(Data(#"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf /"},"session_id":"r1"}"#.utf8))
        inPipe.fileHandleForWriting.closeFile()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        XCTAssertTrue(out.contains(#""behavior": "deny""#) || out.contains(#""behavior":"deny""#), "got: \(out)")
    }
}

extension HookE2ETests {
    /// User answers in the terminal → agent kills the hook → server must fire
    /// onCancel so the notch card dismisses instead of lingering.
    func testHookDeathCancelsPendingRequest() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: hookBinaryPathForExtension))
        let sock = "/tmp/e2e-cx-\(UUID().uuidString.prefix(8)).sock"
        let cancelled = expectation(description: "onCancel fired")
        let server = IPCServer(socketPath: sock,
                               onNotify: { _ in },
                               onRequest: { _, _, _ in /* never decide */ },
                               onCancel: { _ in cancelled.fulfill() })
        try server.start()
        defer { server.stop() }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: hookBinaryPathForExtension)
        p.arguments = ["--source", "claude"]
        p.environment = ProcessInfo.processInfo.environment
            .merging(["VIBENOTCH_SOCKET": sock]) { _, new in new }
        let inPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        inPipe.fileHandleForWriting.write(Data(#"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"x"},"session_id":"cx"}"#.utf8))
        inPipe.fileHandleForWriting.closeFile()

        Thread.sleep(forTimeInterval: 0.5) // let the request register
        p.terminate()                      // Claude cancelling the hook

        wait(for: [cancelled], timeout: 5)
    }
}

extension HookE2ETests {
    /// Codex sends tool_input as a raw STRING and carries prompt/model inline.
    func testCodexStringToolInputAndInlineFields() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: hookBinaryPathForExtension))
        let sock = "/tmp/e2e-cxs-\(UUID().uuidString.prefix(8)).sock"
        let server = IPCServer(socketPath: sock,
                               onNotify: { _ in },
                               onRequest: { _, inbound, complete in
                                   XCTAssertEqual(inbound.detail, "rm -rf build && make",
                                                  "string tool_input must survive")
                                   XCTAssertEqual(inbound.model, "gpt-5.6-sol")
                                   XCTAssertEqual(inbound.userMessage, "ship the release")
                                   XCTAssertEqual(inbound.tty, "ttys009")
                                   complete(VNReply(decision: .allow))
                               })
        try server.start()
        defer { server.stop() }
        let stdin = #"{"hook_event_name":"PermissionRequest","tool_name":"Shell","tool_input":"rm -rf build && make","session_id":"cx2","cwd":"/tmp","model":"gpt-5.6-sol","prompt":"ship the release","terminal_app":"Ghostty","terminal_tty":"/dev/ttys009","permission_mode":"default"}"#
        let out = try runHookForExtension(source: "codex", stdin: stdin, socketPath: sock)
        XCTAssertTrue(out.contains(#""continue":true"#) && out.contains(#""behavior":"allow""#), "got: \(out)")
    }

    func testCodexStopCarriesLastAssistantMessage() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: hookBinaryPathForExtension))
        let sock = "/tmp/e2e-cxn-\(UUID().uuidString.prefix(8)).sock"
        let got = expectation(description: "stop notify")
        let server = IPCServer(socketPath: sock,
                               onNotify: { inbound in
                                   XCTAssertEqual(inbound.event, "Stop")
                                   XCTAssertEqual(inbound.detail, "Release shipped, tests green.")
                                   got.fulfill()
                               },
                               onRequest: { _, _, complete in complete(VNReply(decision: .deny)) })
        try server.start()
        defer { server.stop() }
        _ = try runHookForExtension(source: "codex",
            stdin: #"{"hook_event_name":"Stop","session_id":"cx2","cwd":"/tmp","model":"gpt-5.6-sol","last_assistant_message":"Release shipped, tests green.","permission_mode":"default"}"#,
            socketPath: sock)
        wait(for: [got], timeout: 5)
    }
}
