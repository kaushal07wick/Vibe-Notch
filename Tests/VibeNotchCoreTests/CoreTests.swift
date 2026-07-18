import XCTest
@testable import VibeNotchCore

final class CoreTests: XCTestCase {

    // MARK: Installer — the security-critical config edit

    func testInstallAddsBlockingPermissionRequestHook() {
        let out = ClaudeInstaller.installed(into: [:])
        let hooks = out["hooks"] as? [String: Any]
        let pr = hooks?["PermissionRequest"] as? [[String: Any]]
        let hook = (pr?.first?["hooks"] as? [[String: Any]])?.first
        XCTAssertEqual(hook?["timeout"] as? Int, 86_400, "PermissionRequest must block long enough for a GUI decision")
        XCTAssertTrue((hook?["command"] as? String)?.contains("vibenotch-hook") == true)
    }

    func testInstallIsIdempotent() {
        let once = ClaudeInstaller.installed(into: [:])
        let twice = ClaudeInstaller.installed(into: once)
        let groups = (twice["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]]
        XCTAssertEqual(groups?.count, 1, "installing twice must not duplicate hook groups")
    }

    func testUninstallRemovesOnlyOurHooksAndPreservesOthers() {
        // A settings file with a foreign hook plus unrelated keys.
        let foreign: [String: Any] = [
            "matcher": "*",
            "hooks": [["type": "command", "command": "/opt/other-tool --run"]],
        ]
        let start: [String: Any] = [
            "model": "opus",
            "hooks": ["Stop": [foreign]],
        ]
        let installed = ClaudeInstaller.installed(into: start)
        let cleaned = ClaudeInstaller.uninstalled(from: installed)

        XCTAssertEqual(cleaned["model"] as? String, "opus", "unrelated keys must survive")
        let stop = (cleaned["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 1, "the foreign hook must remain")
        XCTAssertEqual((stop?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String,
                       "/opt/other-tool --run")
        XCTAssertNil((cleaned["hooks"] as? [String: Any])?["PermissionRequest"],
                     "our PermissionRequest hook must be gone")
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

        // request → gets the server's decision
        let req = VNInbound(type: .request, source: "claude", event: "PermissionRequest", tool: "Bash")
        XCTAssertEqual(IPCClient.send(req, socketPath: sock, timeout: 5), .deny)

        // notify → no decision returned
        let note = VNInbound(type: .notify, source: "claude", event: "Stop")
        XCTAssertNil(IPCClient.send(note, socketPath: sock, timeout: 5))
    }
}
