import Foundation
import VibeNotchCore

/// A pending Claude permission request awaiting the user's decision.
struct PendingApproval: Identifiable {
    let id: UUID
    let inbound: VNInbound
    let reply: @Sendable (VNReply) -> Void
    let createdAt = Date()
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
    var gitBranch: String?
    var gitDirty: Bool = false
    var tokensIn: Int = 0    // accumulated over the session's turns
    var tokensOut: Int = 0
    var console: [String] = []  // rolling terminal mirror (commands + output tails)
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
    @Published var hovering = false

    /// Sessions the user chose to Bypass — further requests auto-approve
    /// until the session ends or the app restarts.
    private var bypassedSessions: Set<String> = []

    /// True once a pending approval has waited past the escalation threshold —
    /// the menu-bar badge turns ⚠ and the chime repeats once.
    @Published private(set) var escalated = false
    private var escalationTimer: Timer?

    private let persistURL = VNPaths.data.appendingPathComponent("sessions.json")

    init() {
        loadSessions()
        escalationTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in self.checkEscalation() }
        }
    }

    private func checkEscalation() {
        let threshold = VNSettings.escalationSeconds
        guard threshold > 0, let oldest = pending.first else {
            if escalated { escalated = false }
            return
        }
        if !escalated && Date().timeIntervalSince(oldest.createdAt) > Double(threshold) {
            escalated = true
            SoundManager.shared.play(.permission) // one repeat chime, not a loop
            pushEscalation(oldest)
        }
    }

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
        // Safe-listed simple command → silent auto-approve (flow, not noise).
        if VNSettings.safeListEnabled, approval.inbound.tool == "Bash",
           let command = approval.inbound.detail,
           SafeList.matches(command, patterns: SafeList.patterns()) {
            approval.reply(VNReply(decision: .allow))
            StatsLog.bump("autoApproved")
            return
        }
        pending.append(approval)
        SoundManager.shared.play(.permission)
    }

    func cancel(_ id: UUID) {
        pending.removeAll { $0.id == id }
        if pending.isEmpty { escalated = false }
    }

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
        if pending.isEmpty { escalated = false }
        StatsLog.bump(decision.agentBehavior == .deny ? "denied" : "approved")
    }

    /// Answer an AskUserQuestion card: one selected option label per question.
    func answer(_ approval: PendingApproval, answers: [String]) {
        approval.reply(VNReply(decision: .allow, answers: answers))
        pending.removeAll { $0.id == approval.id }
    }

    /// Fold a hook event into the session's current activity.
    func updateSession(_ i: VNInbound) {
        guard let sid = i.sessionId else { return }

        // The session made progress while an approval card was still up →
        // the user answered in the terminal. The card is stale: drop it so the
        // panel collapses, and don't wait on the (possibly dead) hook socket.
        if ["PreToolUse", "PostToolUse", "PostToolUseFailure", "Stop", "StopFailure",
            "UserPromptSubmit"].contains(i.event) {
            for stale in pending where stale.inbound.sessionId == sid {
                stale.reply(VNReply(decision: .ask)) // no-output defer if the hook still lives
            }
            pending.removeAll { $0.inbound.sessionId == sid }
            if pending.isEmpty { escalated = false }
        }

        if i.event == "SessionEnd" {
            if let s = sessions.removeValue(forKey: sid) { archive(s) }
            bypassedSessions.remove(sid)
            saveSessions()
            return
        }

        // Subagent events adjust the count without disturbing the main status.
        if i.event == "SubagentStart" || i.event == "SubagentStop" {
            guard var s = sessions[sid] else { return }
            s.subagents = max(0, s.subagents + (i.event == "SubagentStart" ? 1 : -1))
            s.updatedAt = Date()
            sessions[sid] = s
            return
        }

        let wasWaiting = sessions[sid]?.event == "Notification"
        if sessions[sid] == nil { StatsLog.bump("sessions") }
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
        if let branch = i.gitBranch { s.gitBranch = branch }
        if let dirty = i.gitDirty { s.gitDirty = dirty }
        s.tokensIn += i.tokensIn ?? 0
        s.tokensOut += i.tokensOut ?? 0
        appendConsole(&s, from: i)
        s.updatedAt = Date()
        sessions[sid] = s
        if i.event == "Notification" && !wasWaiting { SoundManager.shared.play(.waiting) }
        pruneStale()
        saveSessions()
    }

    /// Rolling terminal mirror per session: `$ command`, output tails, replies.
    private func appendConsole(_ s: inout SessionActivity, from i: VNInbound) {
        var lines: [String] = []
        switch i.event {
        case "PreToolUse":
            if let d = i.detail { lines = ["$ " + d] }
        case "PostToolUse", "PostToolUseFailure":
            if let d = i.detail { lines = d.components(separatedBy: "\n").suffix(20).map { String($0) } }
        case "Stop", "StopFailure":
            if let d = i.detail { lines = ["· " + d] }
        default:
            break
        }
        guard !lines.isEmpty else { return }
        s.console.append(contentsOf: lines)
        if s.console.count > 200 { s.console.removeFirst(s.console.count - 200) }
    }

    private func archive(_ s: SessionActivity) {
        SessionArchive.append(ArchivedSession(sessionId: s.sessionId, source: s.source,
                                    folder: s.folder, task: s.task, host: s.host,
                                    startedAt: s.startedAt, endedAt: Date(),
                                    tokensIn: s.tokensIn, tokensOut: s.tokensOut))
    }

    /// Optional phone ping via ntfy.sh — only when the user configured a topic.
    private func pushEscalation(_ approval: PendingApproval) {
        let topic = VNSettings.ntfyTopic
        guard !topic.isEmpty, let url = URL(string: "https://ntfy.sh/\(topic)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let folder = (approval.inbound.cwd as NSString?)?.lastPathComponent ?? "agent"
        request.httpBody = Data("\(folder): \(approval.inbound.tool ?? "permission") awaiting approval".utf8)
        request.setValue("Vibe Notch", forHTTPHeaderField: "Title")
        URLSession.shared.dataTask(with: request).resume()
    }

    private func pruneStale() {
        let cutoff = Date().addingTimeInterval(-3600)
        for (key, s) in sessions where s.updatedAt <= cutoff {
            archive(s)
            sessions.removeValue(forKey: key)
        }
    }

}
