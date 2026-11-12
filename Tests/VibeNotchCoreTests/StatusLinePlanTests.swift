import XCTest
@testable import VibeNotchCore

final class StatusLinePlanTests: XCTestCase {
    func testBridgePlanIsReadOnlyAndRestoresOriginalObject() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = root.appendingPathComponent("settings.json")
        let script = root.appendingPathComponent("bin/statusline.sh")
        let original: [String: Any] = ["type": "command", "command": "printf 'hello'", "padding": 3]
        let before = try JSONSerialization.data(withJSONObject: ["statusLine": original, "theme": "dark"])
        try before.write(to: settings)
        let plan = try StatusLineInstaller.connectionPlan(connecting: true, settingsURL: settings, scriptURL: script)
        XCTAssertEqual(try Data(contentsOf: settings), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: script.path))
        try plan.apply()
        XCTAssertEqual(StatusLineInstaller.currentWrappedCommand(scriptURL: script), "printf 'hello'")
        let again = try StatusLineInstaller.connectionPlan(connecting: true, settingsURL: settings, scriptURL: script)
        XCTAssertTrue(again.changes.isEmpty)
        try StatusLineInstaller.connectionPlan(connecting: false, settingsURL: settings, scriptURL: script).apply()
        let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        XCTAssertEqual((restored["statusLine"] as! [String: Any])["command"] as? String, "printf 'hello'")
        XCTAssertEqual((restored["statusLine"] as! [String: Any])["padding"] as? Int, 3)
        XCTAssertEqual(restored["theme"] as? String, "dark")
    }

    func testMalformedSettingsAreNotReplaced() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = root.appendingPathComponent("settings.json")
        try Data("{broken".utf8).write(to: settings)
        XCTAssertThrowsError(try StatusLineInstaller.connectionPlan(connecting: true, settingsURL: settings, scriptURL: root.appendingPathComponent("bridge")))
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), "{broken")
    }
}
