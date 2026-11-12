import Foundation

/// A short local record of an observed event. A transcript entry describes what
/// a client logged; only the hook channel can carry a live approval request.
public struct ActivityTimelineEntry: Codable, Identifiable, Equatable, Sendable {
    public enum Origin: String, Codable, Sendable { case hook, transcript }
    public enum Kind: String, Codable, Sendable {
        case activity, approvalRequested, approvalDecision, approvalCancelled
    }

    public let id: String
    public let timestamp: Date
    public let sessionID: String
    public let source: String
    public let origin: Origin
    public let kind: Kind
    public let title: String
    public let detail: String?
    public let tool: String?
    /// The action or lifecycle result, not an inference from agent output.
    public let outcome: String?

    public init(id: String = UUID().uuidString, timestamp: Date = Date(), sessionID: String,
                source: String, origin: Origin, kind: Kind = .activity, title: String,
                detail: String? = nil, tool: String? = nil, outcome: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.source = source
        self.origin = origin
        self.kind = kind
        self.title = String(title.prefix(120))
        self.detail = detail.flatMap { $0.isEmpty ? nil : String($0.prefix(600)) }
        self.tool = tool.map { String($0.prefix(80)) }
        self.outcome = outcome.map { String($0.prefix(80)) }
    }

    public static func observed(_ inbound: VNInbound, at timestamp: Date = Date(),
                                origin: Origin, id: String? = nil) -> ActivityTimelineEntry? {
        guard let sessionID = inbound.sessionId else { return nil }
        let title: String
        switch inbound.event {
        case "SessionStart": title = "Session detected"
        case "SessionEnd": title = "Session ended"
        case "UserPromptSubmit": title = "Prompt submitted"
        case "PreToolUse": title = "Tool started"
        case "PostToolUse": title = "Tool returned"
        case "PostToolUseFailure": title = "Tool failed"
        case "Stop": title = "Turn completed"
        case "Interrupted", "TurnAborted": title = "Turn interrupted"
        case "StopFailure": title = "Turn failed"
        case "Notification": title = "Agent notification"
        case "PreCompact": title = "Context compacting"
        case "SubagentStart": title = "Subagent started"
        case "SubagentStop": title = "Subagent finished"
        default: title = inbound.event
        }
        return ActivityTimelineEntry(id: id ?? UUID().uuidString, timestamp: timestamp,
                                     sessionID: sessionID, source: inbound.source, origin: origin,
                                     title: title, detail: inbound.detail ?? inbound.userMessage,
                                     tool: inbound.tool)
    }
}

/// Bounded records, ordered by event time. IDs allow transcript snapshots to be
/// re-read after a restart without manufacturing duplicate activity.
public struct ActivityTimeline: Codable, Sendable {
    public private(set) var entries: [ActivityTimelineEntry]
    public static let maximumEntries = 1000
    public static let maximumPerSession = 200
    public static let retentionSeconds: TimeInterval = 7 * 24 * 60 * 60

    public init(entries: [ActivityTimelineEntry] = [], now: Date = Date()) {
        self.entries = []
        for entry in entries { _ = append(entry, now: now) }
    }

    @discardableResult public mutating func append(_ entry: ActivityTimelineEntry, now: Date = Date()) -> Bool {
        let cutoff = now.addingTimeInterval(-Self.retentionSeconds)
        entries.removeAll { $0.timestamp < cutoff }
        guard entry.timestamp >= cutoff, !entries.contains(where: { $0.id == entry.id }) else { return false }
        entries.append(entry)
        entries.sort { $0.timestamp < $1.timestamp }
        let sameSession = entries.filter { $0.sessionID == entry.sessionID }
        if sameSession.count > Self.maximumPerSession {
            let remove = Set(sameSession.prefix(sameSession.count - Self.maximumPerSession).map(\.id))
            entries.removeAll { remove.contains($0.id) }
        }
        if entries.count > Self.maximumEntries { entries.removeFirst(entries.count - Self.maximumEntries) }
        return true
    }

    public func entries(for sessionID: String) -> [ActivityTimelineEntry] {
        entries.filter { $0.sessionID == sessionID }
    }
}

/// Writes are serialized so a shutdown flush cannot be overwritten by an older
/// queued snapshot. The caller debounces saves; no agent files are written.
public final class ActivityTimelineStorage: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "com.vibenotch.activity-timeline", qos: .utility)

    public init(url: URL) { self.url = url }

    public func load(now: Date = Date()) -> ActivityTimeline {
        queue.sync {
            guard let data = try? Data(contentsOf: url),
                  let saved = try? JSONDecoder().decode(ActivityTimeline.self, from: data) else { return ActivityTimeline() }
            return ActivityTimeline(entries: saved.entries, now: now)
        }
    }

    public func save(_ timeline: ActivityTimeline) {
        queue.async { [url] in Self.write(timeline, to: url) }
    }

    public func flush(_ timeline: ActivityTimeline) {
        queue.sync { Self.write(timeline, to: url) }
    }

    private static func write(_ timeline: ActivityTimeline, to url: URL) {
        guard let data = try? JSONEncoder().encode(timeline) else { return }
        do { try data.write(to: url, options: .atomic) }
        catch { NSLog("VibeNotch: could not save activity timeline: %@", error.localizedDescription) }
    }
}
