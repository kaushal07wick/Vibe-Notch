import XCTest
@testable import VibeNotchCore

final class SessionPhaseTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testTerminalOutcomesRemainDistinct() {
        let outcomes: [String: SessionPhase] = [
            "Stop": .completed, "task_complete": .completed,
            "Interrupted": .interrupted, "turn_aborted": .interrupted,
            "StopFailure": .failed, "PostToolUseFailure": .failed,
            "SessionEnd": .inactive,
        ]
        for (event, expected) in outcomes {
            let phase = SessionPhase.resolve(event: event, updatedAt: now.addingTimeInterval(-500), now: now)
            XCTAssertEqual(phase, expected, event)
            XCTAssertFalse(phase.isBusy)
        }
    }

    func testStaleWorkStopsClaimingAnAgentIsRunning() {
        for event in ["PreToolUse", "PostToolUse", "UserPromptSubmit", "PreCompact"] {
            XCTAssertEqual(SessionPhase.resolve(event: event, updatedAt: now, now: now), .working)
            let stale = SessionPhase.resolve(event: event, updatedAt: now.addingTimeInterval(-91), now: now)
            XCTAssertEqual(stale, .inactive)
            XCTAssertEqual(stale.statusText(event: event, tool: "exec"), "No recent activity")
        }
    }

    func testPendingRequestTakesPriorityOverCompletedOrStaleActivity() {
        for event in ["Stop", "Interrupted", "PreToolUse", "SessionStart"] {
            let phase = SessionPhase.resolve(event: event, updatedAt: now.addingTimeInterval(-500),
                                             now: now, hasPendingRequest: true)
            XCTAssertEqual(phase, .waiting)
            XCTAssertTrue(phase.needsAttention)
            XCTAssertTrue(phase.isBusy)
        }
    }

    func testMetadataAndUnrecognizedEventsStayUnknown() {
        for event in ["SessionStart", "unexpected-event", ""] {
            let phase = SessionPhase.resolve(event: event, updatedAt: now, now: now)
            XCTAssertEqual(phase, .unknown)
            XCTAssertFalse(phase.isBusy)
            XCTAssertFalse(phase.needsAttention)
        }
    }

    func testWaitingFreshnessAndQueuePriority() {
        XCTAssertEqual(SessionPhase.resolve(event: "Notification", updatedAt: now, now: now), .waiting)
        XCTAssertEqual(SessionPhase.resolve(event: "PermissionRequest", updatedAt: now.addingTimeInterval(-91), now: now), .inactive)
        XCTAssertLessThan(SessionPhase.waiting.sortPriority, SessionPhase.working.sortPriority)
        XCTAssertLessThan(SessionPhase.working.sortPriority, SessionPhase.completed.sortPriority)
    }
}
