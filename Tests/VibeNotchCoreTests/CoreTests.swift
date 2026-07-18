import XCTest
@testable import VibeNotchCore

final class CoreTests: XCTestCase {

    private let claudeEvents = Agents.claudeEvents
    private let command = "/bin/sh -c 'vibenotch-hook --source claude'"

    // MARK: Claude-schema installer — the security-critical config edit

    func testInstallAddsBlockingPermissionRequestHook() {
        let out = AgentHookInstaller.jsonHooksInstalled(into: [:], events: claudeEvents, command: command)
        let hooks = out["hooks"] as? [String: Any]
        let pr = hooks?["PermissionRequest"] as? [[String: Any]]
        let hook = (pr?.first?["hooks"] as? [[String: Any]])?.first
        XCTAssertEqual(hook?["timeout"] as? Int, 86_400, "PermissionRequest must block long enough for a GUI decision")
        XCTAssertTrue((hook?["command"] as? String)?.contains("vibenotch-hook") == true)
    }

    func testInstallIsIdempotent() {
        let once = AgentHookInstaller.jsonHooksInstalled(into: [:], events: claudeEvents, command: command)
        let twice = AgentHookInstaller.jsonHooksInstalled(into: once, events: claudeEvents, command: command)
        let groups = (twice["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]]
        XCTAssertEqual(groups?.count, 1, "installing twice must not duplicate hook groups")
    }

    func testUninstallRemovesOnlyOurHooksAndPreservesOthers() {
        let foreign: [String: Any] = [
            "matcher": "*",
            "hooks": [["type": "command", "command": "/opt/other-tool --run"]],
        ]
        let start: [String: Any] = ["model": "opus", "hooks": ["Stop": [foreign]]]
        let installed = AgentHookInstaller.jsonHooksInstalled(into: start, events: claudeEvents, command: command)
        let cleaned = AgentHookInstaller.jsonHooksUninstalled(from: installed)

        XCTAssertEqual(cleaned["model"] as? String, "opus", "unrelated keys must survive")
        let stop = (cleaned["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 1, "the foreign hook must remain")
        XCTAssertEqual((stop?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String,
                       "/opt/other-tool --run")
        XCTAssertNil((cleaned["hooks"] as? [String: Any])?["PermissionRequest"],
                     "our PermissionRequest hook must be gone")
    }

    // MARK: Cursor installer

    func testCursorInstallUninstallRoundTrip() {
        let events = ["beforeShellExecution", "stop"]
        let foreign: [String: Any] = ["hooks": ["stop": [["command": "/opt/other"]]]]

        let installed = AgentHookInstaller.cursorHooksInstalled(into: foreign, events: events, command: command)
        let stop = (installed["hooks"] as? [String: Any])?["stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 2, "ours appended alongside the foreign entry")

        let again = AgentHookInstaller.cursorHooksInstalled(into: installed, events: events, command: command)
        XCTAssertEqual(((again["hooks"] as? [String: Any])?["stop"] as? [[String: Any]])?.count, 2, "idempotent")

        let cleaned = AgentHookInstaller.cursorHooksUninstalled(from: installed)
        let cleanedStop = (cleaned["hooks"] as? [String: Any])?["stop"] as? [[String: Any]]
        XCTAssertEqual(cleanedStop?.count, 1)
        XCTAssertEqual(cleanedStop?.first?["command"] as? String, "/opt/other")
        XCTAssertNil((cleaned["hooks"] as? [String: Any])?["beforeShellExecution"])
    }

    // MARK: Registry sanity

    func testEveryAgentHasUniqueIDAndConfig() {
        let ids = Agents.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "agent ids must be unique")
        for spec in Agents.all {
            XCTAssertFalse(spec.configDir.isEmpty)
            XCTAssertFalse(spec.configFile.isEmpty)
        }
    }

    // MARK: IPC round-trip

    func testIPCRequestReturnsDecisionAndNotifyDoesNot() throws {
        let sock = NSTemporaryDirectory() + "vn-test-\(UUID().uuidString).sock"
        let server = IPCServer(
            socketPath: sock,
            onNotify: { _ in },
            onRequest: { _, _, complete in complete(.deny) } // auto-deny
        )
        try server.start()
        defer { server.stop() }

        let req = VNInbound(type: .request, source: "claude", event: "PermissionRequest", tool: "Bash")
        XCTAssertEqual(IPCClient.send(req, socketPath: sock, timeout: 5), .deny)

        let note = VNInbound(type: .notify, source: "claude", event: "Stop")
        XCTAssertNil(IPCClient.send(note, socketPath: sock, timeout: 5))
    }
}
