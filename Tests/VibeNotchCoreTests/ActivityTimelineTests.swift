import XCTest
@testable import VibeNotchCore

final class ActivityTimelineTests: XCTestCase {
    func testOrdersDeduplicatesAndBoundsObservedEntries() {
        let now = Date()
        var timeline = ActivityTimeline(now: now)
        let inbound = VNInbound(type: .notify, source: "codex", event: "Interrupted", tool: "exec",
                                detail: String(repeating: "x", count: 1000), sessionId: "session")
        let later = ActivityTimelineEntry.observed(inbound, at: now, origin: .transcript, id: "snapshot")!
        XCTAssertTrue(timeline.append(later, now: now))
        XCTAssertFalse(timeline.append(later, now: now), "Re-reading a transcript snapshot is not new activity")
        let earlier = ActivityTimelineEntry(id: "earlier", timestamp: now.addingTimeInterval(-1),
            sessionID: "session", source: "codex", origin: .hook, title: "Prompt submitted")
        timeline.append(earlier, now: now)
        XCTAssertEqual(timeline.entries.map(\.id), ["earlier", "snapshot"])
        XCTAssertEqual(later.detail?.count, 600)
        XCTAssertEqual(later.title, "Turn interrupted")
        XCTAssertEqual(later.kind, .activity, "Transcript activity never manufactures an approval")
        XCTAssertEqual(later.origin, .transcript)
        for n in 0..<250 {
            timeline.append(ActivityTimelineEntry(id: "event-\(n)", timestamp: now.addingTimeInterval(Double(n)),
                sessionID: "session", source: "codex", origin: .hook, title: "Tool returned"), now: now)
        }
        XCTAssertEqual(timeline.entries(for: "session").count, ActivityTimeline.maximumPerSession)
        XCTAssertEqual(timeline.entries.last?.id, "event-249")
        XCTAssertEqual(timeline.entries.first?.id, "event-50")
    }

    func testGlobalBoundAndRetention() {
        let now = Date()
        var timeline = ActivityTimeline(now: now)
        for n in 0..<1010 {
            timeline.append(ActivityTimelineEntry(id: "event-\(n)", timestamp: now.addingTimeInterval(Double(n)),
                sessionID: "session-\(n)", source: "claude", origin: .hook, title: "Activity"), now: now)
        }
        XCTAssertEqual(timeline.entries.count, ActivityTimeline.maximumEntries)
        XCTAssertEqual(timeline.entries.first?.id, "event-10")
        let expired = ActivityTimelineEntry(timestamp: now.addingTimeInterval(-ActivityTimeline.retentionSeconds - 1),
            sessionID: "expired", source: "codex", origin: .transcript, title: "Old observation")
        XCTAssertFalse(timeline.append(expired, now: now))
        let aged = ActivityTimeline(entries: timeline.entries, now: now.addingTimeInterval(ActivityTimeline.retentionSeconds + 2000))
        XCTAssertTrue(aged.entries.isEmpty)
    }

    func testPersistsDistinctDecisionsAndShutdownFlushWinsOverQueuedSave() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = ActivityTimelineStorage(url: root.appendingPathComponent("activity.json"))
        let now = Date()
        var timeline = ActivityTimeline(now: now)
        for (n, outcome) in ["deny", "ask", "cancelled", "held", "undone", "allow"].enumerated() {
            timeline.append(ActivityTimelineEntry(timestamp: now.addingTimeInterval(Double(n)), sessionID: "session",
                source: "codex", origin: .hook, kind: outcome == "cancelled" ? .approvalCancelled : .approvalDecision,
                title: "Decision", outcome: outcome), now: now)
            if n == 0 { storage.save(timeline) }
        }
        storage.flush(timeline)
        let restored = storage.load(now: now)
        XCTAssertEqual(restored.entries, timeline.entries)
        XCTAssertEqual(restored.entries.map(\.outcome), ["deny", "ask", "cancelled", "held", "undone", "allow"])
        XCTAssertEqual(restored.entries[2].kind, .approvalCancelled)
        XCTAssertEqual(storage.load(now: now.addingTimeInterval(ActivityTimeline.retentionSeconds + 10)).entries.count, 0)
    }
}
