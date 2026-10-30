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
    /// The file tray is open — it holds the panel up (you're dragging things in and out).
    @Published var showTray = false
    /// An open multiple-choice question in a live Codex session, and which of its questions is next.
    @Published var codexQuestion: CodexQuestion?
    @Published var codexQuestionStep = 0
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

    init() {
        loadSessions()
        escalationTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in self.checkEscalation() }
        }
        reapTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { _ in
            Task { @MainActor in self.reapDead() }
        }
        questionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in self.pollCodexQuestions() }
        }
    }

    /// Sessions whose agent process is verifiably still running on their tty.
    private var liveIDs: Set<String> = []
    private var reapTimer: Timer?
    private var questionTimer: Timer?

    private func pollCodexQuestions() {
        guard sessions.values.contains(where: { $0.source == "codex" && liveIDs.contains($0.id) }) else {
            if codexQuestion != nil { codexQuestion = nil }
            return
        }
        Task.detached {
            let found = CodexQuestionWatcher.scan()
            await MainActor.run { [weak self] in
                guard let self else { return }
                let live = self.sessions.values.filter { $0.source == "codex" && self.liveIDs.contains($0.id) }
                let match = found.first { q in !self.hiddenCodexCalls.contains(q.id) && live.contains { $0.cwd == q.cwd } }
                if match?.id != self.codexQuestion?.id { self.codexQuestionStep = 0 }
                if self.codexQuestion != match { self.codexQuestion = match }
            }
        }
    }

    /// The live Codex session a question belongs to (matched by working directory).
    func codexSession(for q: CodexQuestion) -> SessionActivity? {
        sessions.values.filter { $0.source == "codex" && $0.cwd == q.cwd && liveIDs.contains($0.id) }
            .max { $0.updatedAt < $1.updatedAt }
    }

    /// Types the choice into Codex's own prompt, then moves to the next question (or hides the card).
    func answerCodex(_ q: CodexQuestion, option index: Int, text: String? = nil) {
        guard let session = codexSession(for: q) else { return }
        Task {
            _ = await TerminalControl.send("\(index + 1)", to: session, allowActiveTab: true)
            if let text, !text.isEmpty {
                try? await Task.sleep(for: .milliseconds(450))
                _ = await TerminalControl.send(text, to: session, allowActiveTab: true)
            }
        }
        codexQuestionStep += 1
        if codexQuestionStep >= q.items.count { hideCodexQuestion(q) }
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
        let all = Array(sessions.values)
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
                self.liveIDs = live
                for id in dead { if let s = self.sessions.removeValue(forKey: id) { self.archive(s) } }
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
            // sessions waiting on you float to the top
            let a = ["Notification", "PermissionRequest"].contains($0.event), b = ["Notification", "PermissionRequest"].contains($1.event)
            return a != b ? a : $0.updatedAt > $1.updatedAt
        }
    }

    var activeSession: SessionActivity? { activeSessions.first }

    /// Keep the notch visible only while something actually needs attention:
    /// a pending card, a session working, or one waiting for you. A paused or
    /// finished session goes quiet → the notch hides (clears fullscreen video).
    /// ponytail: 90s quiet-window = "paused"; a long single tool call also
    /// hides mid-run, which is the desired behavior for the movie case.
    var isBusy: Bool {
        if !pending.isEmpty { return true }
        let live = Date().addingTimeInterval(-90)
        return sessions.values.contains {
            $0.updatedAt > live &&
            ["PreToolUse", "PostToolUse", "UserPromptSubmit", "Notification"].contains($0.event)
        }
    }

    func enqueue(_ approval: PendingApproval) {
        // Bypassed session → auto-approve silently, no card.
        if let sid = approval.inbound.sessionId, bypassedSessions.contains(sid) {
            approval.reply(VNReply(decision: .allow))
            return
        }
        // Timeboxed YOLO mode: everything auto-approves until it expires.
        if Date().timeIntervalSince1970 < VNSettings.yoloUntil {
            approval.reply(VNReply(decision: .allow))
            StatsLog.bump("yolo")
            return
        }
        // Below the notch threshold → the terminal prompt handles it. The
        // hook replies nothing, so the agent's own flow takes over cleanly.
        let risk = RiskGrader.grade(tool: approval.inbound.tool, detail: approval.inbound.detail)
        let ranks: [String: Int] = ["low": 0, "medium": 1, "high": 2]
        if ranks[risk.rawValue, default: 0] < ranks[VNSettings.notchMinRisk, default: 0] {
            approval.reply(VNReply(decision: .ask))
            StatsLog.bump("deferredToTerminal")
            return
        }
        // Safe-listed simple command → silent auto-approve (flow, not noise).
        let policy = Policies.policy(for: approval.inbound.cwd, in: Policies.load())
        if VNSettings.safeListEnabled, policy.safeList, approval.inbound.tool == "Bash",
           let command = approval.inbound.detail,
           SafeList.matches(command, patterns: SafeList.patterns()) {
            approval.reply(VNReply(decision: .allow))
            StatsLog.bump("autoApproved")
            return
        }
        pending.append(approval)
        if !privacyHold { SoundManager.shared.play(.permission) }
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

    func resolve(_ approval: PendingApproval, _ decision: VNDecision, permissions: [String]? = nil) {
        pending.removeAll { $0.id == approval.id }
        if pending.isEmpty { escalated = false }

        let hold = VNSettings.undoSeconds
        guard hold > 0 else { commit(approval, decision, permissions: permissions); return }
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
        for approval in pending { approval.reply(VNReply(decision: .ask)) }
        pending.removeAll()
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
        approval.reply(VNReply(decision: decision, answers: answers, permissions: permissions))
        StatsLog.bump(decision.agentBehavior == .deny ? "denied" : "approved")
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
        let turnMoved = ["Stop", "StopFailure", "UserPromptSubmit", "Notification"].contains(i.event)
        let ranThisTool = ["PostToolUse", "PostToolUseFailure"].contains(i.event)
        if turnMoved || ranThisTool {
            let isStale: (PendingApproval) -> Bool = { card in
                card.inbound.sessionId == sid && (turnMoved || card.inbound.tool == i.tool)
            }
            for stale in pending where isStale(stale) {
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
        case "Stop", "StopFailure":
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
