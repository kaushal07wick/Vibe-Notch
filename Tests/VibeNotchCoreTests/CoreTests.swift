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
            onRequest: { _, _, complete in complete(VNReply(decision: .deny)) } // auto-deny
        )
        try server.start()
        defer { server.stop() }

        let req = VNInbound(type: .request, source: "claude", event: "PermissionRequest", tool: "Bash")
        XCTAssertEqual(IPCClient.send(req, socketPath: sock, timeout: 5)?.decision, .deny)

        let note = VNInbound(type: .notify, source: "claude", event: "Stop")
        XCTAssertNil(IPCClient.send(note, socketPath: sock, timeout: 5))
    }
}

extension CoreTests {
    // MARK: Usage parsing

    func testClaudeUsageParsing() throws {
        let json = #"{"five_hour":{"used_percentage":26.4,"resets_at":1784500000},"seven_day":{"utilization":42.0,"resets_at":"2026-07-23T10:00:00Z"}}"#
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rl-\(UUID()).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let usage = try XCTUnwrap(UsageLoader.loadClaude(from: url))
        XCTAssertEqual(usage.windows.count, 2)
        XCTAssertEqual(usage.windows[0].label, "5h")
        XCTAssertEqual(usage.windows[0].usedPercentage, 26.4, accuracy: 0.01)
        XCTAssertNotNil(usage.windows[1].resetsAt, "ISO8601 resets_at must parse")
        XCTAssertEqual(usage.peak?.label, "7d", "peak = highest used percentage")
    }

    func testCodexUsageParsing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID())/a")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let lines = [
            #"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":11.0,"window_minutes":300,"resets_at":1784500000},"secondary":{"used_percent":67.0,"window_minutes":10080}}}}"#,
        ].joined(separator: "\n")
        try lines.write(to: dir.appendingPathComponent("rollout-2026.jsonl"), atomically: true, encoding: .utf8)

        let usage = try XCTUnwrap(UsageLoader.loadCodex(sessionsDir: dir.deletingLastPathComponent()))
        XCTAssertEqual(usage.windows.map(\.label), ["5h", "7d"])
        XCTAssertEqual(usage.peak?.usedPercentage ?? 0, 67.0, accuracy: 0.01)
    }
}

extension CoreTests {
    func testPermissionRuleBuilding() {
        XCTAssertEqual(PermissionRules.rule(tool: "Bash", detail: "npm run build && npm test"), "Bash(npm:*)")
        XCTAssertEqual(PermissionRules.rule(tool: "Bash", detail: nil), "Bash")
        XCTAssertEqual(PermissionRules.rule(tool: "WebFetch", detail: "https://x.com"), "WebFetch")
        XCTAssertEqual(VNDecision.alwaysAllow.agentBehavior, .allow)
        XCTAssertEqual(VNDecision.bypass.agentBehavior, .allow)
        XCTAssertEqual(VNDecision.deny.agentBehavior, .deny)
    }
}

extension CoreTests {
    func testKimiTOMLInstallUninstallRoundTrip() {
        let events = [AgentSpec.HookEvent("PermissionRequest", timeout: 86_400), AgentSpec.HookEvent("Stop")]
        let original = "model = \"kimi-k2\"\n\n[tui]\ntheme = \"dark\"\n"

        let installed = AgentHookInstaller.kimiInstalled(into: original, events: events, command: "/x/vibenotch-hook --source kimi")
        XCTAssertTrue(installed.contains("model = \"kimi-k2\""), "existing config preserved")
        XCTAssertEqual(installed.components(separatedBy: "[[hooks]]").count - 1, 2, "one block per event")
        XCTAssertTrue(installed.contains("timeout = 86400"), "PermissionRequest keeps its long timeout")

        let twice = AgentHookInstaller.kimiInstalled(into: installed, events: events, command: "/x/vibenotch-hook --source kimi")
        XCTAssertEqual(twice.components(separatedBy: "[[hooks]]").count - 1, 2, "idempotent")

        let cleaned = AgentHookInstaller.kimiUninstalled(from: installed)
        XCTAssertFalse(cleaned.contains("[[hooks]]"))
        XCTAssertTrue(cleaned.contains("[tui]"), "foreign tables preserved")
    }
}

extension CoreTests {
    func testOpenCodePluginRegistrationRoundTrip() {
        let start: [String: Any] = ["plugin": ["/x/other.js"], "theme": "dark"]
        let reg = AgentHookInstaller.opencodeRegistered(into: start, pluginPath: "/y/plugins/vibenotch.js")
        XCTAssertEqual((reg["plugin"] as? [String])?.count, 2)
        let again = AgentHookInstaller.opencodeRegistered(into: reg, pluginPath: "/y/plugins/vibenotch.js")
        XCTAssertEqual((again["plugin"] as? [String])?.count, 2, "idempotent")
        let un = AgentHookInstaller.opencodeUnregistered(from: reg)
        XCTAssertEqual(un["plugin"] as? [String], ["/x/other.js"])
        XCTAssertEqual(un["theme"] as? String, "dark")
    }
}
