import XCTest
@testable import VibeNotchCore

final class IPCSafetyTests: XCTestCase {
    func testSocketIsPrivateAndTransportsDecision() throws {
        let path = "/tmp/vn-private-\(UUID().uuidString.prefix(12)).sock"
        let server = IPCServer(socketPath: path, onNotify: { _ in },
                               onRequest: { _, _, reply in reply(VNReply(decision: .deny)) })
        try server.start()
        defer { server.stop() }
        let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as! NSNumber
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
        let request = VNInbound(type: .request, source: "claude", event: "PermissionRequest", tool: "Bash")
        XCTAssertEqual(IPCClient.send(request, socketPath: path, timeout: 2)?.decision, .deny)
    }

    func testInvalidPathsAreRejectedBeforeCreatingSocket() {
        let request = VNInbound(type: .request, source: "claude", event: "PermissionRequest")
        for path in ["/tmp/" + String(repeating: "x", count: 200), "/tmp/vn\0invalid"] {
            let server = IPCServer(socketPath: path, onNotify: { _ in }, onRequest: { _, _, _ in })
            XCTAssertThrowsError(try server.start())
            XCTAssertNil(IPCClient.send(request, socketPath: path, timeout: 1))
        }
    }

    func testStoppedServerFallsBackToAgent() throws {
        let path = "/tmp/vn-stopped-\(UUID().uuidString.prefix(12)).sock"
        let server = IPCServer(socketPath: path, onNotify: { _ in }, onRequest: { _, _, _ in })
        try server.start()
        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        let request = VNInbound(type: .request, source: "claude", event: "PermissionRequest")
        XCTAssertNil(IPCClient.send(request, socketPath: path, timeout: 1))
    }
}
