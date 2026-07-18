import Foundation
import VibeNotchCore

/// A pending Claude permission request awaiting the user's decision.
struct PendingApproval: Identifiable {
    let id: UUID
    let inbound: VNInbound
    let reply: @Sendable (VNDecision) -> Void
}

/// What one agent session is currently doing — updated on every hook event.
struct SessionActivity: Identifiable {
    let sessionId: String
    var source: String
    var folder: String?
    var task: String?
    var userMessage: String?
    var tool: String?     // the tool it's running right now (from PreToolUse)
    var detail: String?   // command / message / last assistant text
    var event: String     // last hook event — drives the status label
    var terminal: String?
    var startedAt: Date
    var updatedAt: Date
    var id: String { sessionId }
}

/// Drives the notch UI: the approval queue, live session activity, hover state,
/// and a brief post-decision flash.
@MainActor
final class EventStore: ObservableObject {
    @Published var pending: [PendingApproval] = []
    @Published var sessions: [String: SessionActivity] = [:]
    @Published var flash: VNDecision?
    @Published var hovering = false

    /// Sessions active in the last 30 minutes, newest first.
    var activeSessions: [SessionActivity] {
        let cutoff = Date().addingTimeInterval(-1800)
        return sessions.values.filter { $0.updatedAt > cutoff }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var activeSession: SessionActivity? { activeSessions.first }

    func enqueue(_ approval: PendingApproval) { pending.append(approval) }

    func cancel(_ id: UUID) { pending.removeAll { $0.id == id } }

    func resolve(_ approval: PendingApproval, _ decision: VNDecision) {
        approval.reply(decision)
        pending.removeAll { $0.id == approval.id }
        showFlash(decision)
    }

    /// Fold a hook event into the session's current activity.
    func updateSession(_ i: VNInbound) {
        guard let sid = i.sessionId else { return }
        var s = sessions[sid] ?? SessionActivity(sessionId: sid, source: i.source, event: i.event, startedAt: Date(), updatedAt: Date())
        s.source = i.source
        if let cwd = i.cwd { s.folder = (cwd as NSString).lastPathComponent }
        if let t = i.title { s.task = t }
        if let u = i.userMessage { s.userMessage = u }
        s.tool = i.tool                 // nil clears the "running X" when the turn moves on
        if let d = i.detail { s.detail = d }
        s.event = i.event
        s.terminal = i.terminal ?? s.terminal
        s.updatedAt = Date()
        sessions[sid] = s
        pruneStale()
    }

    private func pruneStale() {
        let cutoff = Date().addingTimeInterval(-3600)
        sessions = sessions.filter { $0.value.updatedAt > cutoff }
    }

    private func showFlash(_ decision: VNDecision) {
        flash = decision
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            if pending.isEmpty { flash = nil }
        }
    }
}
