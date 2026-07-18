import Foundation
import VibeNotchCore

/// A pending Claude permission request awaiting the user's decision.
struct PendingApproval: Identifiable {
    let id: UUID
    let inbound: VNInbound
    let reply: @Sendable (VNReply) -> Void
}

/// What one agent session is currently doing — updated on every hook event.
struct SessionActivity: Identifiable, Codable {
    let sessionId: String
    var source: String
    var folder: String?
    var task: String?
    var userMessage: String?
    var tool: String?     // the tool it's running right now (from PreToolUse)
    var detail: String?   // command / message / last assistant text
    var event: String     // last hook event — drives the status label
    var terminal: String?
    var tty: String?
    var termMeta: [String: String]?
    var model: String?
    var host: String?        // remote hostname (SSH sessions)
    var subagents: Int = 0   // live subagent count (SubagentStart/Stop)
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

    /// Sessions the user chose to Bypass — further requests auto-approve
    /// until the session ends or the app restarts.
    private var bypassedSessions: Set<String> = []

    private let persistURL = VNPaths.data.appendingPathComponent("sessions.json")

    init() { loadSessions() }

    /// Restore sessions from disk (dropping anything stale) so a relaunch
    /// doesn't lose the live picture.
    private func loadSessions() {
        guard let data = try? Data(contentsOf: persistURL),
              let saved = try? JSONDecoder().decode([String: SessionActivity].self, from: data)
        else { return }
        let cutoff = Date().addingTimeInterval(-3600)
        sessions = saved.filter { $0.value.updatedAt > cutoff }
    }

    private func saveSessions() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: persistURL, options: .atomic)
    }

    /// Sessions active in the last 30 minutes, newest first.
    var activeSessions: [SessionActivity] {
        let cutoff = Date().addingTimeInterval(-1800)
        return sessions.values.filter { $0.updatedAt > cutoff }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var activeSession: SessionActivity? { activeSessions.first }

    func enqueue(_ approval: PendingApproval) {
        // Bypassed session → auto-approve silently, no card.
        if let sid = approval.inbound.sessionId, bypassedSessions.contains(sid) {
            approval.reply(VNReply(decision: .allow))
            return
        }
        pending.append(approval)
        SoundManager.shared.play(.permission)
    }

    func cancel(_ id: UUID) { pending.removeAll { $0.id == id } }

    /// User dismissed a session row (bin button) — remove it from the list.
    /// The session reappears on its next hook event.
    func dismiss(sessionId: String) {
        sessions.removeValue(forKey: sessionId)
        saveSessions()
    }

    func resolve(_ approval: PendingApproval, _ decision: VNDecision) {
        switch decision {
        case .alwaysAllow where approval.inbound.host != nil:
            break // remote session — the rule belongs on the server, not here
        case .alwaysAllow:
            // Persist a permission rule so the agent stops asking for this.
            PermissionRules.addAllowRule(source: approval.inbound.source,
                                         tool: approval.inbound.tool ?? "Bash",
                                         detail: approval.inbound.detail)
        case .bypass:
            if let sid = approval.inbound.sessionId { bypassedSessions.insert(sid) }
        default:
            break
        }
        approval.reply(VNReply(decision: decision))
        pending.removeAll { $0.id == approval.id }
        showFlash(decision.agentBehavior)
    }

    /// Answer an AskUserQuestion card: one selected option label per question.
    func answer(_ approval: PendingApproval, answers: [String]) {
        approval.reply(VNReply(decision: .allow, answers: answers))
        pending.removeAll { $0.id == approval.id }
        showFlash(.allow)
    }

    /// Fold a hook event into the session's current activity.
    func updateSession(_ i: VNInbound) {
        guard let sid = i.sessionId else { return }
        if i.event == "SessionEnd" { sessions.removeValue(forKey: sid); bypassedSessions.remove(sid); saveSessions(); return }

        // Subagent events adjust the count without disturbing the main status.
        if i.event == "SubagentStart" || i.event == "SubagentStop" {
            guard var s = sessions[sid] else { return }
            s.subagents = max(0, s.subagents + (i.event == "SubagentStart" ? 1 : -1))
            s.updatedAt = Date()
            sessions[sid] = s
            return
        }

        let wasWaiting = sessions[sid]?.event == "Notification"
        var s = sessions[sid] ?? SessionActivity(sessionId: sid, source: i.source, event: i.event, startedAt: Date(), updatedAt: Date())
        s.source = i.source
        if let cwd = i.cwd { s.folder = (cwd as NSString).lastPathComponent }
        if let t = i.title { s.task = t }
        if let u = i.userMessage { s.userMessage = u }
        s.tool = i.tool                 // nil clears the "running X" when the turn moves on
        if let d = i.detail { s.detail = d }
        s.event = i.event
        s.terminal = i.terminal ?? s.terminal
        s.tty = i.tty ?? s.tty
        s.termMeta = i.termMeta ?? s.termMeta
        s.model = i.model ?? s.model
        s.host = i.host ?? s.host
        s.updatedAt = Date()
        sessions[sid] = s
        if i.event == "Notification" && !wasWaiting { SoundManager.shared.play(.waiting) }
        pruneStale()
        saveSessions()
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
