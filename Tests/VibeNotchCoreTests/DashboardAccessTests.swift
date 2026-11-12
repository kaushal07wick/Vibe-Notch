import XCTest
@testable import VibeNotchCore

final class DashboardAccessTests: XCTestCase {
    private func request(_ path: String, method: String = "GET", host: String = "127.0.0.1:4141", extra: String = "") -> String {
        "\(method) \(path) HTTP/1.1\r\nHost: \(host)\r\n\(extra)\r\n"
    }
    func testReadOnlyRoutesRequireLaunchKey() {
        XCTAssertEqual(DashboardAccess.route(request: request("/?t=secret"), token: "secret", port: 4141), .page)
        XCTAssertEqual(DashboardAccess.route(request: request("/state.json?t=secret"), token: "secret", port: 4141), .state)
        XCTAssertEqual(DashboardAccess.route(request: request("/state.json"), token: "secret", port: 4141), .rejected(403))
        XCTAssertEqual(DashboardAccess.route(request: request("/state.json?t=old"), token: "secret", port: 4141), .rejected(403))
    }
    func testMutationAndCrossOriginRequestsAreRejected() {
        for action in ["approve", "deny", "approve_all", "undo"] {
            XCTAssertEqual(DashboardAccess.route(request: request("/\(action)?t=secret"), token: "secret", port: 4141), .rejected(404))
            XCTAssertEqual(DashboardAccess.route(request: request("/\(action)?t=secret", method: "POST"), token: "secret", port: 4141), .rejected(405))
        }
        XCTAssertEqual(DashboardAccess.route(request: request("/?t=secret", host: "attacker.example:4141"), token: "secret", port: 4141), .rejected(403))
        XCTAssertEqual(DashboardAccess.route(request: request("/?t=secret", extra: "Origin: https://attacker.example\r\n"), token: "secret", port: 4141), .rejected(403))
        XCTAssertEqual(DashboardAccess.route(request: request("/?t=secret", extra: "Origin: http://127.0.0.1:4141\r\n"), token: "secret", port: 4141), .page)
    }
    func testAmbiguousAndAbsoluteTargetsAreRejected() {
        XCTAssertEqual(DashboardAccess.route(request: request("/?t=secret&t=secret"), token: "secret", port: 4141), .rejected(403))
        XCTAssertEqual(DashboardAccess.route(request: request("http://attacker.example/?t=secret"), token: "secret", port: 4141), .rejected(403))
        XCTAssertEqual(DashboardAccess.route(request: request("/?t=secret", extra: "Host: attacker.example\r\n"), token: "secret", port: 4141), .rejected(400))
    }
}
