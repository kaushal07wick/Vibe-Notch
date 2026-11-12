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
    var cwd: String?
    var folder: String?
    /// A name given inside the agent (/rename, Codex thread name); wins over the auto task text.
    var customTitle: String?
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
    var imagePath: String?      // last image a tool touched
    var todos: [VNTodo]?        // latest TodoWrite checklist
    var contextTokens: Int?     // context window fill after the latest turn
    var diffStat: [Int]?        // [files, added, removed] vs HEAD at the latest turn end
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
    @Published var timelineSessionID: String?
    @Published private(set) var timeline = ActivityTimeline()
    @Published var hovering = false
    /// The file tray is open — it holds the panel up (you're dragging things in and out).
    @Published var showTray = false
    /// The now-playing + calendar page is open (also holds the panel up).
    @Published var showWidgets = false
    /// An open multiple-choice question in a live Codex session, and which of its questions is next.
    @Published var codexQuestion: CodexQuestion?
    @Published var codexQuestionStep = 0
    @Published var sendingCodexAnswer = false
    @Published var codexAnswerError: String?
    /// A session whose turn just ended — the panel peeks at it for a few seconds.
    @Published var justFinished: String?
    private var hiddenCodexCalls: Set<String> = []

    /// Sessions the user chose to Bypass — further requests auto-approve
    /// until the session ends or the app restarts.
    private var bypassedSessions: Set<String> = []

    /// A decision held for the undo window — the agent hasn't been told yet.
    struct PendingUndo {
        let approval: PendingApproval
        let decision: VNDecision
        var permissions: [String]? = nil
        let task: Task<Void, Never>
    }
    @Published var undo: PendingUndo?

    /// "While you were away" summary; auto-clears.
    @Published var digest: String?

    /// Increments on tool activity — drives ambient animations cheaply.
    @Published var activityTick = 0

    /// Screen-share privacy hold: cards queue silently while true.
    @Published var privacyHold = false {
        didSet {
            guard oldValue != privacyHold, !privacyHold, !pending.isEmpty else { return }
            SoundManager.shared.play(.permission) // share ended — surface the queue
        }
    }

    /// True once a pending approval has waited past the escalation threshold —
    /// the menu-bar badge turns ⚠ and the chime repeats once.
    @Published private(set) var escalated = false
    private var escalationTimer: Timer?

    private let persistURL = VNPaths.data.appendingPathComponent("sessions.json")
    private let timelineStorage = ActivityTimelineStorage(url: VNPaths.data.appendingPathComponent("activity-timeline.json"))
    private var timelineSaveTask: Task<Void, Never>?
    private let codexActivity = CodexActivityReader()
    private var codexActivityTask: Task<Void, Never>?
    private var observedCodexIDs: Set<String> = []

    init() {
        timeline = timelineStorage.load()
        loadSessions()
        escalationTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in self.checkEscalation() }
        }
        reapTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { _ in
            Task { @MainActor in self.reapDead() }
        }
        questionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in self.pollCodexActivity(); self.pollCodexQuestions(); self.pollTitles() }
        }
        pollCodexActivity()
    }

    private func pollCodexActivity() {
        guard codexActivityTask == nil else { return }
        codexActivityTask = Task { [weak self, codexActivity] in
            let snapshots = await codexActivity.scan()
            guard let self else { return }
            defer { self.codexActivityTask = nil }
            self.liveIDs.subtract(self.observedCodexIDs)
            self.observedCodexIDs = Set(snapshots.compactMap { $0.inbound.sessionId })
            self.liveIDs.formUnion(self.observedCodexIDs)
            for snapshot in snapshots {
                let i = snapshot.inbound
                guard let id = i.sessionId,
                      self.sessions[id].map({ $0.updatedAt < snapshot.updatedAt }) ?? true else { continue }
                var s = self.sessions[id] ?? SessionActivity(sessionId: id, source: "codex", event: i.event,
                                                            startedAt: snapshot.updatedAt, updatedAt: snapshot.updatedAt)
                s.cwd = i.cwd
                s.folder = i.cwd.map { ($0 as NSString).lastPathComponent }
                s.event = i.event
                s.tool = i.tool
                s.detail = i.detail
                s.userMessage = i.userMessage ?? s.userMessage
                s.updatedAt = snapshot.updatedAt
                self.sessions[id] = s
                self.record(ActivityTimelineEntry.observed(i, at: snapshot.updatedAt, origin: .transcript,
                    id: "transcript:\(id):\(snapshot.updatedAt.timeIntervalSince1970.bitPattern):\(i.event)"))
                // Transcript observations never resolve approvals or synthesize
                // permission cards; those still require the live hook channel.
                self.saveSessions()
            }
        }
    }

    /// Sessions whose agent process is verifiably still running on their tty.
    private var liveIDs: Set<String> = []
    private var reapTimer: Timer?
    private var questionTimer: Timer?

    private func pollTitles() {
        let live = activeSessions.map { ($0.id, $0.source) }
        guard !live.isEmpty else { return }
        Task.detached {
            let found = SessionTitles.titles(for: live.map { (id: $0.0, source: $0.1) })
            await MainActor.run { [weak self] in
                guard let self else { return }
                for (id, title) in found where self.sessions[id]?.customTitle != title { self.sessions[id]?.customTitle = title }
            }
        }
    }

    private var questionScanTask: Task<Void, Never>?

    private func pollCodexQuestions() {
        guard !sendingCodexAnswer, questionScanTask == nil else { return }
        guard sessions.values.contains(where: { $0.source == "codex" && liveIDs.contains($0.id) }) else {
            if codexQuestion != nil { codexQuestion = nil }
            return
        }
        questionScanTask = Task.detached {
            let found = CodexQuestionWatcher.scan()
            await MainActor.run { [weak self] in
                guard let self else { return }
                defer { self.questionScanTask = nil }
                guard !self.sendingCodexAnswer else { return }
                let live = self.sessions.values.filter { $0.source == "codex" && self.liveIDs.contains($0.id) }
                let match = found.first { q in !self.hiddenCodexCalls.contains(q.id) && live.contains { $0.id == q.sessionID } }
                if match?.id != self.codexQuestion?.id || match?.items != self.codexQuestion?.items {
                    self.codexQuestionStep = 0
                    self.codexAnswerError = nil
                }

                if self.codexQuestion != match { self.codexQuestion = match }
            }
        }
    }

    /// Questions belong to an exact session, even when several chats share a folder.
    func codexSession(for q: CodexQuestion) -> SessionActivity? {
        guard let session = sessions[q.sessionID], session.source == "codex", liveIDs.contains(session.id) else { return nil }
        return session
    }

    /// Advance only after Codex acknowledges the reply (or the legacy terminal accepts it).
    func answerCodex(_ q: CodexQuestion, option index: Int, text: String? = nil) {
        guard !sendingCodexAnswer, codexQuestion == q,
              let session = codexSession(for: q), session.host == nil,
              q.items.indices.contains(codexQuestionStep),
              let reply = q.reply(step: codexQuestionStep, option: index, text: text) else { return }
        let step = codexQuestionStep
        sendingCodexAnswer = true
        codexAnswerError = nil
        Task {
            let sent: Bool
            if q.async {
                sent = await CodexQuestionResponder.send(reply, sessionID: q.sessionID)
            } else if let text {
                // Tab focuses the legacy prompt's notes without submitting a numbered choice first.
                let focused: Bool
                if q.items[step].options.isEmpty { focused = true }
                else { focused = await TerminalControl.press(
                    tmux: "Tab", keyCode: 48, in: session, purpose: "editing Codex's answer") }
                if focused {
                    sent = await TerminalControl.send(text, to: session, allowActiveTab: true)
                } else { sent = false }
            } else {
                // Number keys select AND submit; an extra Enter would answer the next question too.
                sent = await TerminalControl.send("\(index + 1)", to: session, allowActiveTab: true, submit: false)
            }
            sendingCodexAnswer = false
            guard codexQuestion?.id == q.id, codexQuestion?.sessionID == q.sessionID else { return }
            guard sent else {
                codexAnswerError = "Couldn’t deliver the answer to Codex. Your answer is still here; try again."
                return
            }
            codexQuestionStep += 1
            if codexQuestionStep >= q.items.count { hideCodexQuestion(q) }
        }
    }

    func hideCodexQuestion(_ q: CodexQuestion) {
        hiddenCodexCalls.insert(q.id)
        codexQuestion = nil
    }

    /// A session is a live agent only while claude/codex is still on its tty.
    /// Agents that exit without a SessionEnd (Codex has none, ^C, closed tab)
    /// move to history instead of lingering as "sessions" for half an hour.
    /// ponytail: one `ps` per tty every 8s; sessions with no tty (SSH, simulated)
    /// keep the old time-based rule.
    private func reapDead() {
        let all = sessions.values.filter { !observedCodexIDs.contains($0.id) }
        // one tty hosts one agent: only its newest session is live, older ids are history
        let byTTY = Dictionary(grouping: all.filter { $0.tty != nil }, by: { $0.tty! })
            .mapValues { $0.sorted { $0.updatedAt > $1.updatedAt } }
        let orphans = all.filter { $0.source == "codex" && $0.tty == nil && $0.cwd == nil && $0.host == nil }.map(\.id)
        // Codex runs its hooks from a daemon with no tty, so match those by cwd.
        let codexByCwd = Dictionary(grouping: all.filter { $0.source == "codex" && $0.tty == nil && $0.host == nil && $0.cwd != nil },
                                    by: { $0.cwd! })
        guard !byTTY.isEmpty || !codexByCwd.isEmpty || !orphans.isEmpty else { return }
        Task.detached(priority: .utility) {
            func run(_ exe: String, _ args: [String]) -> String {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
                guard (try? p.run()) != nil else { return "" }
                let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                p.waitUntilExit()
                return out
            }
            var live: Set<String> = [], dead: Set<String> = []
            dead.formUnion(orphans)
            for (tty, group) in byTTY {
                let out = run("/bin/ps", ["-t", tty, "-o", "command="]).lowercased()
                let up = out.contains("claude") || out.contains("codex")
                for (n, s) in group.enumerated() { if up && n == 0 { live.insert(s.id) } else { dead.insert(s.id) } }
            }
            if !codexByCwd.isEmpty {
                // running codex CLIs (they sit on a tty; the daemon does not) → their cwds
                let pids = run("/bin/ps", ["-axo", "pid=,tty=,comm="]).split(separator: "\n").compactMap { line -> String? in
                    let f = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                    return f.count == 3 && f[1] != "??" && f[2].hasSuffix("/codex") ? String(f[0]) : nil
                }
                var procs: [String: Int] = [:]   // cwd → running codex count
                if !pids.isEmpty {
                    for line in run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-Fn", "-p", pids.joined(separator: ",")]).split(separator: "\n")
                    where line.hasPrefix("n") { procs[String(line.dropFirst()), default: 0] += 1 }
                }
                for (cwd, group) in codexByCwd {
                    let keep = group.sorted { $0.updatedAt > $1.updatedAt }
                    for (n, s) in keep.enumerated() { if n < procs[cwd, default: 0] { live.insert(s.id) } else { dead.insert(s.id) } }
                }
            }
            await MainActor.run { [live, dead] in
                self.liveIDs = live.union(self.observedCodexIDs)
                for id in dead where !self.observedCodexIDs.contains(id) {
                    if let s = self.sessions.removeValue(forKey: id) { self.archive(s) }
                }
                if !dead.isEmpty { self.saveSessions() }
            }
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
            UserHooks.fire("escalation", ["tool": oldest.inbound.tool ?? "",
                                          "session": oldest.inbound.sessionId ?? ""])
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

    private var saveScheduled = false

    /// Debounced: many events per second must not mean many disk writes.
    private func saveSessions() {
        guard !saveScheduled else { return }
        saveScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            self.saveScheduled = false
            let snapshot = self.sessions
            Task.detached(priority: .utility) {
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                try? data.write(to: VNPaths.data.appendingPathComponent("sessions.json"), options: .atomic)
            }
        }
    }

    /// Sessions active in the last 30 minutes, newest first.
    var activeSessions: [SessionActivity] {
        let cutoff = Date().addingTimeInterval(-1800)
        return sessions.values.filter { $0.updatedAt > cutoff || liveIDs.contains($0.id) }.sorted {
            let a = phase(for: $0).sortPriority, b = phase(for: $1).sortPriority
            return a != b ? a < b : $0.updatedAt > $1.updatedAt
        }
    }

    var activeSession: SessionActivity? { activeSessions.first }

    /// A real pending request takes precedence over an observed activity state.
    func phase(for session: SessionActivity, now: Date = Date()) -> SessionPhase {
        let hasApproval = pending.contains { $0.inbound.sessionId == session.id }
        let hasQuestion = codexQuestion.flatMap { codexSession(for: $0)?.id } == session.id
        return session.phase(at: now, hasPendingRequest: hasApproval || hasQuestion)
    }

    var isBusy: Bool {
        !pending.isEmpty || codexQuestion != nil || activeSessions.contains { phase(for: $0).isBusy }
    }

    private func record(_ entry: ActivityTimelineEntry?) {
        guard let entry, timeline.append(entry) else { return }
        guard timelineSaveTask == nil else { return }
        timelineSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            self.timelineSaveTask = nil
            self.timelineStorage.save(self.timeline)
        }
    }

    private func recordApproval(_ approval: PendingApproval, kind: ActivityTimelineEntry.Kind,
                                title: String, outcome: String? = nil, detail: String? = nil) {
        record(ActivityTimelineEntry(sessionID: approval.inbound.sessionId ?? "request-\(approval.id)",
            source: approval.inbound.source, origin: .hook, kind: kind, title: title,
            detail: detail ?? approval.inbound.detail, tool: approval.inbound.tool, outcome: outcome))
    }

    func enqueue(_ approval: PendingApproval) {
        recordApproval(approval, kind: .approvalRequested, title: "Approval requested")
        // Bypassed session → auto-approve silently, no card.
        if let sid = approval.inbound.sessionId, bypassedSessions.contains(sid) {
            recordApproval(approval, kind: .approvalDecision, title: "Allowed by session bypass", outcome: "allow")
            approval.reply(VNReply(decision: .allow))
            return
        }
        // Timeboxed YOLO mode: everything auto-approves until it expires.
        if Date().timeIntervalSince1970 < VNSettings.yoloUntil {
            recordApproval(approval, kind: .approvalDecision, title: "Allowed by timed bypass", outcome: "allow")
            approval.reply(VNReply(decision: .allow))
            StatsLog.bump("yolo")
            return
        }
        // Below the notch threshold → the terminal prompt handles it. The
        // hook replies nothing, so the agent's own flow takes over cleanly.
        let risk = RiskGrader.grade(tool: approval.inbound.tool, detail: approval.inbound.detail)
        let ranks: [String: Int] = ["low": 0, "medium": 1, "high": 2]
        if ranks[risk.rawValue, default: 0] < ranks[VNSettings.notchMinRisk, default: 0] {
            recordApproval(approval, kind: .approvalDecision, title: "Deferred to terminal", outcome: "ask")
            approval.reply(VNReply(decision: .ask))
            StatsLog.bump("deferredToTerminal")
            return
        }
        // Safe-listed simple command → silent auto-approve (flow, not noise).
        let policy = Policies.policy(for: approval.inbound.cwd, in: Policies.load())
        if VNSettings.safeListEnabled, policy.safeList, approval.inbound.tool == "Bash",
           let command = approval.inbound.detail,
           SafeList.matches(command, patterns: SafeList.patterns()) {
            recordApproval(approval, kind: .approvalDecision, title: "Allowed by safe list", outcome: "allow")
            approval.reply(VNReply(decision: .allow))
            StatsLog.bump("autoApproved")
            return
        }
        pending.append(approval)
        if !privacyHold { SoundManager.shared.play(.permission) }
    }

    func cancel(_ id: UUID) {
        if let held = undo, held.approval.id == id {
            held.task.cancel()
            undo = nil
            recordApproval(held.approval, kind: .approvalCancelled, title: "Request closed", outcome: "cancelled",
                           detail: "The request closed before the held decision was sent.")
        }
        if let approval = pending.first(where: { $0.id == id }) {
            recordApproval(approval, kind: .approvalCancelled, title: "Request closed", outcome: "cancelled",
                           detail: "The request connection closed. No decision was sent.")
        }
        pending.removeAll { $0.id == id }
        if pending.isEmpty { escalated = false }
    }

    /// User dismissed a session row (bin button) — remove it from the list.
    /// The session reappears on its next hook event.
    func dismiss(sessionId: String) {
        sessions.removeValue(forKey: sessionId)
        saveSessions()
    }

    func resolve(_ approval: PendingApproval, _ decision: VNDecision, permissions: [String]? = nil) {
        pending.removeAll { $0.id == approval.id }
        if pending.isEmpty { escalated = false }

        let hold = VNSettings.undoSeconds
        guard hold > 0 else { commit(approval, decision, permissions: permissions); return }
        recordApproval(approval, kind: .approvalDecision, title: "Decision held for undo", outcome: "held")
        // Hold the reply so the click can be undone; the agent just waits.
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.commit(approval, decision, permissions: permissions)
                self?.undo = nil
            }
        }
        undo = PendingUndo(approval: approval, decision: decision, permissions: permissions, task: task)
    }

    /// Quit-time flush: a held undo commits (the user did decide); undecided
    /// cards defer to the terminal (`ask`) so no agent is ever stranded
    /// waiting on a dead app.
    func flushForShutdown() {
        if let held = undo {
            held.task.cancel()
            commit(held.approval, held.decision, permissions: held.permissions)
            undo = nil
        }
        for approval in pending {
            recordApproval(approval, kind: .approvalDecision, title: "Returned to terminal on quit", outcome: "ask")
            approval.reply(VNReply(decision: .ask))
        }
        pending.removeAll()
        timelineSaveTask?.cancel()
        timelineSaveTask = nil
        timelineStorage.flush(timeline)
        if let data = try? JSONEncoder().encode(sessions) {
            try? data.write(to: persistURL, options: .atomic) // synchronous — we're quitting
        }
    }

    /// Take the last decision back — re-queues the card; the agent never knew.
    func undoLast() {
        guard let held = undo else { return }
        held.task.cancel()
        undo = nil
        pending.insert(held.approval, at: 0)
        recordApproval(held.approval, kind: .approvalDecision, title: "Decision withdrawn", outcome: "undone",
                       detail: "The agent was not answered; the request is waiting again.")
    }

    /// Approve every pending card (optionally one session's). No undo window —
    /// batch is an explicit, deliberate act.
    func approveAll(sessionId: String? = nil) {
        let matches = pending.filter { sessionId == nil || $0.inbound.sessionId == sessionId }
        for approval in matches { commit(approval, .allow) }
        pending.removeAll { m in matches.contains { $0.id == m.id } }
        if pending.isEmpty { escalated = false }
    }

    /// Apply side effects and actually answer the agent.
    private func commit(_ approval: PendingApproval, _ decision: VNDecision, answers: [String]? = nil, permissions: [String]? = nil) {
        let policy = Policies.policy(for: approval.inbound.cwd, in: Policies.load())
        switch decision {
        case .alwaysAllow where approval.inbound.host != nil || !policy.alwaysAllow:
            break // remote session or strict project — no persisted rule
        case .bypass where !policy.bypass:
            break // strict project — this click is allow-once only
        case .alwaysAllow:
            PermissionRules.addAllowRule(source: approval.inbound.source,
                                         tool: approval.inbound.tool ?? "Bash",
                                         detail: approval.inbound.detail)
        case .bypass:
            if let sid = approval.inbound.sessionId { bypassedSessions.insert(sid) }
        default:
            break
        }
        let title: String
        switch decision {
        case .deny: title = "Approval denied"
        case .ask: title = "Deferred to terminal"
        case .allow: title = "Allowed once"
        case .alwaysAllow: title = "Allowed with persistent rule"
        case .bypass: title = "Allowed with session bypass"
        }
        recordApproval(approval, kind: .approvalDecision, title: title, outcome: decision.rawValue)
        approval.reply(VNReply(decision: decision, answers: answers, permissions: permissions))
        if decision.agentBehavior != .ask {
            StatsLog.bump(decision.agentBehavior == .deny ? "denied" : "approved")
        }
        UserHooks.fire("approval", ["decision": decision.rawValue,
                                    "tool": approval.inbound.tool ?? "",
                                    "detail": approval.inbound.detail ?? "",
                                    "session": approval.inbound.sessionId ?? ""])
    }

    /// Build the while-you-were-away digest.
    func showDigest(since: Date) {
        let finished = sessions.values.filter { $0.updatedAt > since && ($0.event == "Stop" || $0.event == "StopFailure") }.count
        let waiting = pending.count
        guard finished > 0 || waiting > 0 else { return }
        var parts: [String] = []
        if finished > 0 { parts.append("\(finished) finished") }
        if waiting > 0 { parts.append("\(waiting) waiting for you") }
        digest = "While you were away: " + parts.joined(separator: " · ")
        Task {
            try? await Task.sleep(for: .seconds(5))
            digest = nil
        }
    }

    /// Answer an AskUserQuestion card: one selected option label per question.
    /// Answering is a decision like any other — it went around `commit`, so it
    /// never counted in the stats, never fired the user's `on-approval` hook,
    /// and left `escalated` stuck on after clearing the last card.
    func answer(_ approval: PendingApproval, answers: [String]) {
        pending.removeAll { $0.id == approval.id }
        if pending.isEmpty { escalated = false }
        commit(approval, .allow, answers: answers)
    }

    /// Fold a hook event into the session's current activity.
    func updateSession(_ i: VNInbound) {
        guard let sid = i.sessionId else { return }
        if ["UserPromptSubmit", "SessionEnd", "Interrupted"].contains(i.event),
           let question = codexQuestion, question.sessionID == sid {
            hideCodexQuestion(question)
        }
        record(ActivityTimelineEntry.observed(i, origin: .hook))

        // The session made progress while an approval card was still up →
        // the user answered in the terminal. The card is stale: drop it so the
        // panel collapses, and don't wait on the (possibly dead) hook socket.
        //
        // Only cards this event actually invalidates. Dropping every card for
        // the session killed live siblings: Claude runs tools in parallel, so
        // tool B's PreToolUse would cancel tool A's card while A was still
        // genuinely waiting on the user.
        // PreToolUse is deliberately NOT a trigger: it is the one event that
        // routinely arrives *alongside* a live card rather than after it. The
        // hook's socket closing (onCancel) is the real terminal-answer signal;
        // this is only the belt-and-braces path.
        // ponytail: matched on tool name — the payloads carry no tool_use_id, so
        // two concurrent calls to the SAME tool still can't be told apart. Match
        // on the id instead if the agents ever start sending one.
        // Notification is NOT a trigger either: Claude fires it right as a question or
        // permission dialog opens ("needs your attention"), which dropped the live card
        // and sent the user back to the terminal to answer.
        let turnMoved = ["Stop", "StopFailure", "Interrupted", "UserPromptSubmit"].contains(i.event)
        let ranThisTool = ["PostToolUse", "PostToolUseFailure"].contains(i.event)
        if turnMoved || ranThisTool {
            let isStale: (PendingApproval) -> Bool = { card in
                card.inbound.sessionId == sid && (turnMoved || card.inbound.tool == i.tool)
            }
            if let held = undo, isStale(held.approval) {
                held.task.cancel()
                undo = nil
                recordApproval(held.approval, kind: .approvalCancelled, title: "Agent moved on", outcome: "cancelled",
                               detail: "The request ended before the held decision was sent.")
                held.approval.reply(VNReply(decision: .ask))
            }
            for stale in pending where isStale(stale) {
                recordApproval(stale, kind: .approvalCancelled, title: "Agent moved on", outcome: "cancelled",
                               detail: "Activity invalidated this request. No approval was granted.")
                stale.reply(VNReply(decision: .ask)) // no-output defer if the hook still lives
            }
            pending.removeAll(where: isStale)
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
        if i.event == "Stop", sessions[sid]?.event != "Stop" {
            justFinished = sid
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                if self?.justFinished == sid { self?.justFinished = nil }
            }
        }
        if sessions[sid] == nil { StatsLog.bump("sessions") }
        var s = sessions[sid] ?? SessionActivity(sessionId: sid, source: i.source, event: i.event, startedAt: Date(), updatedAt: Date())
        s.source = i.source
        if let cwd = i.cwd { s.cwd = cwd; s.folder = (cwd as NSString).lastPathComponent }
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
        if let img = i.imagePath { s.imagePath = img }
        if let todos = i.todos { s.todos = todos }
        if let c = i.contextTokens { s.contextTokens = c }
        if i.event == "Stop" { s.diffStat = i.diffStat }
        s.tokensIn += i.tokensIn ?? 0
        s.tokensOut += i.tokensOut ?? 0
        appendConsole(&s, from: i)
        s.updatedAt = Date()
        sessions[sid] = s
        if i.event == "PreToolUse" || i.event == "PostToolUse" { activityTick += 1 }
        if i.event == "Stop" { UserHooks.fire("stop", ["session": sid, "folder": s.folder ?? ""]) }
        if i.event == "Notification" && !wasWaiting {
            SoundManager.shared.play(.waiting)
            UserHooks.fire("waiting", ["session": sid, "folder": s.folder ?? ""])
        }
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
        case "Stop", "StopFailure", "Interrupted":
            if let d = i.detail { lines = ["· " + d] }
        default:
            break
        }
        guard !lines.isEmpty else { return }
        // 200 lines was the only cap, and a line has no length limit — one
        // heredoc pushed a live session to 55KB, re-serialized on every save.
        // Nothing renders past a couple of hundred characters anyway.
        s.console.append(contentsOf: lines.map { $0.count > 300 ? $0.prefix(300) + "…" : $0 })
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
        // No Approve/Deny action buttons: they pointed at http://<hostname>:<port>,
        // but the dashboard binds 127.0.0.1 only, so a phone could never reach
        // them — every tap failed silently. Approving remotely means exposing the
        // approve endpoint off-loopback, which local-first deliberately doesn't do.
        URLSession.shared.dataTask(with: request).resume()
    }

    private func pruneStale() {
        let cutoff = Date().addingTimeInterval(-3600)
        for (key, s) in sessions where s.updatedAt <= cutoff && !liveIDs.contains(key) {
            archive(s)
            sessions.removeValue(forKey: key)
        }
    }

}
