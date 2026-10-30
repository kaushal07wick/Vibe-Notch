import XCTest
@testable import VibeNotchCore

final class TerminalCommandTests: XCTestCase {
    func testExecutionWaitsStopsOnFailureAndTimesOut() async throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let touch = ["/usr/bin/touch", marker.path]
        let failed = await TerminalCommand.run([["/usr/bin/false"], touch])
        XCTAssertFalse(failed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "Never submit Enter after failed input")
        let succeeded = await TerminalCommand.run([touch, ["/bin/test", "-f", marker.path]])
        XCTAssertTrue(succeeded, "Later steps must see earlier steps completed")
        let timedOut = await TerminalCommand.run([["/bin/sleep", "5"]], timeout: 0.05)
        XCTAssertFalse(timedOut)
        let missing = await TerminalCommand.run([["/nonexistent/vibenotch-test"]])
        XCTAssertFalse(missing)
    }

    func testResumeQuotesArgumentsAndRejectsInvalidTargets() {
        XCTAssertEqual(TerminalCommand.resume(source: "codex", id: "a'b;$(false)", cwd: "/tmp/a b"),
                       "cd '/tmp/a b' && codex resume 'a'\\''b;$(false)'")
        XCTAssertEqual(TerminalCommand.resume(source: "claude", id: "session", cwd: "/tmp"),
                       "cd '/tmp' && claude --resume 'session'")
        XCTAssertNil(TerminalCommand.resume(source: "unknown", id: "id", cwd: "/tmp"))
        XCTAssertNil(TerminalCommand.resume(source: "codex", id: "--all", cwd: "/tmp"))
        XCTAssertNil(TerminalCommand.resume(source: "claude", id: "id", cwd: "relative"))
        XCTAssertTrue(TerminalCommand.validTTY("/dev/ttys003"))
        XCTAssertTrue(TerminalCommand.validTTY("ttys003"))
        for tty in ["", "-A", "/dev/tty\"", "ttys003\n", "/dev/pts/0"] {
            XCTAssertFalse(TerminalCommand.validTTY(tty))
            XCTAssertFalse(InjectionPlan.make(terminal: "Terminal", tty: tty, meta: [:], text: "hello").isSupported)
        }
    }
}
