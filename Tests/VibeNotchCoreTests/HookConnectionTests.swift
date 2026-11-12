import XCTest
@testable import VibeNotchCore

final class HookConnectionTests: XCTestCase {
    private func fixture(_ agent: String = "claude") throws -> (URL, AgentHookInstaller, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vibenotch-hooks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("bundled-hook")
        try Data("test helper".utf8).write(to: source)
        let installer = AgentHookInstaller(Agents.byID(agent)!, configDirectory: root.appendingPathComponent("config"),
                                           hookBinary: root.appendingPathComponent("bin/vibenotch-hook"))
        return (root, installer, source)
    }

    func testHealthRequiresActualEventsAndExecutable() throws {
        let (root, installer, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config/settings.json")
        try ConfigJSON.write(["note": "vibenotch"], to: config)
        XCTAssertEqual(installer.health.state, .notConnected)
        let plan = try installer.connectionPlan(connecting: true, hookBinarySource: source)
        XCTAssertTrue(plan.reviewText.contains(config.path))
        XCTAssertTrue(plan.reviewText.contains("PermissionRequest"))
        XCTAssertEqual(ConfigJSON.read(config)?["note"] as? String, "vibenotch", "Planning is read-only")
        let backups = try plan.apply()
        XCTAssertFalse(backups.isEmpty)
        XCTAssertEqual(installer.health.state, .configured)
        var json = ConfigJSON.read(config)!
        var hooks = json["hooks"] as! [String: Any]
        hooks.removeValue(forKey: "PermissionRequest"); json["hooks"] = hooks
        try ConfigJSON.write(json, to: config)
        XCTAssertEqual(installer.health.state, .needsRepair)
        XCTAssertTrue(installer.health.issues.joined().contains("PermissionRequest"))
        try installer.connectionPlan(connecting: true, hookBinarySource: source).apply()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: root.appendingPathComponent("bin/vibenotch-hook").path)
        XCTAssertEqual(installer.health.state, .needsRepair)
        try installer.connectionPlan(connecting: true, hookBinarySource: source).apply()
        XCTAssertEqual(installer.health.state, .configured)
    }

    func testHealthRejectsWrongMatcherAndShortTimeout() throws {
        let (root, installer, source) = try fixture("codex")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config/hooks.json")
        try installer.connectionPlan(connecting: true, hookBinarySource: source).apply()
        var json = ConfigJSON.read(config)!
        var hooks = json["hooks"] as! [String: Any]
        var starts = hooks["SessionStart"] as! [[String: Any]]
        starts[0]["matcher"] = "unsupported-event"
        hooks["SessionStart"] = starts; json["hooks"] = hooks
        try ConfigJSON.write(json, to: config)
        XCTAssertEqual(installer.health.state, .needsRepair)
        XCTAssertTrue(installer.health.issues.joined().contains("SessionStart"))
        try installer.connectionPlan(connecting: true, hookBinarySource: source).apply()
        json = ConfigJSON.read(config)!; hooks = json["hooks"] as! [String: Any]
        var permission = hooks["PermissionRequest"] as! [[String: Any]]
        var entries = permission[0]["hooks"] as! [[String: Any]]
        entries[0]["timeout"] = 1; permission[0]["hooks"] = entries
        hooks["PermissionRequest"] = permission; json["hooks"] = hooks
        try ConfigJSON.write(json, to: config)
        XCTAssertEqual(installer.health.state, .needsRepair)
        XCTAssertTrue(installer.health.issues.joined().contains("PermissionRequest"))
    }

    func testDisconnectPreservesAriaEvenInMixedHookGroup() throws {
        let (root, installer, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config/settings.json")
        let aria = "/Applications/Aria/aria-notch-hook.sh"
        let other = "/opt/other-hook"
        try ConfigJSON.write(["model": "custom", "hooks": ["Stop": [["matcher": "*", "hooks": [
            ["type": "command", "command": aria], ["type": "command", "command": installer.hookCommand],
            ["type": "command", "command": other]]]]]], to: config)
        try installer.connectionPlan(connecting: true, hookBinarySource: source).apply()
        try installer.connectionPlan(connecting: false).apply()
        let result = ConfigJSON.read(config)!
        XCTAssertEqual(result["model"] as? String, "custom")
        let groups = (result["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        let commands = groups.flatMap { $0["hooks"] as! [[String: Any]] }.compactMap { $0["command"] as? String }
        XCTAssertEqual(commands, [aria, other])
        XCTAssertEqual(installer.health.state, .notConnected)
    }

    func testMalformedConfigIsNotOverwritten() throws {
        let (root, installer, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = dir.appendingPathComponent("settings.json")
        let content = Data("{broken".utf8)
        try content.write(to: config)
        XCTAssertEqual(installer.health.state, .needsRepair)
        XCTAssertThrowsError(try installer.connectionPlan(connecting: true, hookBinarySource: source))
        XCTAssertEqual(try Data(contentsOf: config), content)
    }

    func testReviewConflictPreventsAllWrites() throws {
        let (root, installer, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try installer.connectionPlan(connecting: true, hookBinarySource: source)
        let config = root.appendingPathComponent("config/settings.json")
        try ConfigJSON.write(["new": true], to: config)
        XCTAssertThrowsError(try plan.apply())
        XCTAssertEqual(ConfigJSON.read(config)?["new"] as? Bool, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("bin/vibenotch-hook").path))
    }

    func testCodexFlagIsReviewedBackedUpAndRepaired() throws {
        let (root, installer, source) = try fixture("codex")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config/config.toml")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "[features] # existing section\nhooks\t= false\nother = true\n".write(to: config, atomically: true, encoding: .utf8)
        let plan = try installer.connectionPlan(connecting: true, hookBinarySource: source)
        XCTAssertTrue(plan.reviewText.contains(config.path))
        let backups = try plan.apply()
        XCTAssertTrue(backups.contains { $0.path.hasPrefix(config.path + ".vibenotch-") })
        XCTAssertEqual(installer.health.state, .configured)
        XCTAssertTrue(try String(contentsOf: config, encoding: .utf8).contains("other = true"))
        try "[features]\nhooks = false\n".write(to: config, atomically: true, encoding: .utf8)
        XCTAssertEqual(installer.health.state, .needsRepair)
    }

    func testBackupFailureLeavesTargetsUnchanged() throws {
        let (root, installer, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("config")
        let config = dir.appendingPathComponent("settings.json")
        try ConfigJSON.write(["model": "keep"], to: config)
        let before = try Data(contentsOf: config)
        let plan = try installer.connectionPlan(connecting: true, hookBinarySource: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        XCTAssertThrowsError(try plan.apply())
        XCTAssertEqual(try Data(contentsOf: config), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("bin/vibenotch-hook").path))
    }
}
