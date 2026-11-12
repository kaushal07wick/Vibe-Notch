import SwiftUI
import VibeNotchCore

/// Shows what active agent sessions are doing right now (or an idle pill).
/// One session → detail card; several + hover → the SESSIONS list.
struct ActivityCard: View {
    @ObservedObject var store: EventStore
    @Environment(\.vnInterfaceStyle) private var interfaceStyle
    let sessions: [SessionActivity]
    let full: Bool
    var onDismiss: (String) -> Void = { _ in }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            if interfaceStyle != .classic {
                StyledSessionBoard(store: store, sessions: sessions, full: full, style: interfaceStyle,
                                   now: context.date, onDismiss: onDismiss)
            } else if sessions.isEmpty {
                idlePill
            } else if sessions.count > 1 && full {
                listCard(at: context.date)
            } else {
                singleCard(sessions[0], at: context.date)
            }
        }
    }

    // MARK: Idle

    private var idlePill: some View {
        HStack(spacing: 12) {
            PixelGhost(mood: .idle, px: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready when you are").font(VNFont.ui(13, .semibold))
                Text(AgentConnections.anyConnected ? "Start a coding session to see it here." : "Connect your agents in Settings → Integrations.")
                    .font(VNFont.ui(11)).foregroundStyle(VNColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
        }
        .padding(EdgeInsets(top: 4, leading: 16, bottom: 10, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Single session

    private func singleCard(_ s: SessionActivity, at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                AgentIcon(source: s.source, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(sessionTitle(folder: s.folder, task: s.customTitle ?? s.task))
                            .font(VNFont.ui(12.5, .semibold)).lineLimit(1).truncationMode(.tail)
                        GitChip(branch: s.gitBranch, dirty: s.gitDirty)
                        if let c = s.contextTokens { ContextChip(tokens: c) }
                    }
                    if let user = s.userMessage {
                        Text("You: \(user)").font(VNFont.ui(10.5)).foregroundStyle(VNColor.muted)
                            .lineLimit(full ? 3 : 1).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                PillCluster(source: s.source, terminal: s.terminal, tty: s.tty, meta: s.termMeta ?? [:],
                            showJump: s.terminal != nil)
                SessionTimelineButton { store.timelineSessionID = s.id }
            }
            SessionStatusLine(s: s, full: full, phase: store.phase(for: s, now: now))
        }
        .padding(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
        .frame(width: VNSettings.effectivePanelWidth - 20, alignment: .leading)
            }

    // MARK: Session list

    private func listCard(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, s in
                        SessionRow(store: store, s: s, phase: store.phase(for: s, now: now), onDismiss: onDismiss)
                        if index < sessions.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.055))
                                .frame(height: 1)
                        }
                    }
                }
        }
        .padding(EdgeInsets(top: 2, leading: 0, bottom: 8, trailing: 0))
        .frame(width: VNSettings.effectivePanelWidth, alignment: .leading)
    }
}

// MARK: - Status line (spinner/icon + label + terminal block)

/// The "what is it doing" line: status glyph + label, and the real terminal
/// text (command, output, or the agent's message) in a mono block.
struct SessionStatusLine: View {
    let s: SessionActivity
    let full: Bool
    let phase: SessionPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StatusGlyph(phase: phase, size: 10)
                Text(phase.statusText(event: s.event, tool: s.tool))
                    .font(VNFont.ui(11.5, .medium)).foregroundStyle(phase.tint)
                if phase == .completed, let d = s.diffStat, d.count == 3 {
                    (Text("\(d[0]) file\(d[0] == 1 ? "" : "s") ").foregroundStyle(VNColor.paper.opacity(0.7))
                     + Text("+\(d[1]) ").foregroundStyle(VNColor.go) + Text("−\(d[2])").foregroundStyle(VNColor.stop))
                        .font(VNFont.sysMono(10.5, .medium))
                }
                Spacer(minLength: 0)
                if s.subagents > 0 {
                    Text("\(s.subagents) subagent\(s.subagents == 1 ? "" : "s")")
                        .font(VNFont.sysMono(10, .medium)).foregroundStyle(VNColor.running.opacity(0.85))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(VNColor.running.opacity(0.12), in: Capsule())
                }
                if full, s.tokensIn + s.tokensOut > 0 {
                    Text("↓\(kFmt(s.tokensIn)) ↑\(kFmt(s.tokensOut))")
                        .font(VNFont.sysMono(9.5, .medium))
                        .foregroundStyle(VNColor.paper.opacity(0.35))
                }
            }
            if full, let todos = s.todos, !todos.isEmpty { TodoList(todos: todos) }
            // full view shows the rolling console mirror (real commands +
            // output tails); brief keeps just the latest detail
            if full, !s.console.isEmpty {
                TerminalBlock(text: s.console.suffix(14).joined(separator: "\n"), lines: 14)
                LinkChipRow(text: s.detail)
            } else if let detail = s.detail, !detail.isEmpty, s.event != "Notification" {
                TerminalBlock(text: detail, prompt: s.event == "PreToolUse", lines: full ? 8 : 3)
                LinkChipRow(text: detail)
            }
        }
    }

}

/// A terminal-style block — the tail of the real command output/message, in mono.
struct TerminalBlock: View {
    let text: String
    var prompt = false
    let lines: Int

    var body: some View {
        let tail = text.components(separatedBy: "\n").suffix(lines).joined(separator: "\n")
        Text(prompt ? "$ \(tail)" : tail)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(Color(hex: 0xC8CDD4))
            .textSelection(.enabled)
            .lineLimit(lines).truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(VNColor.ink2, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(VNColor.hair))
    }
}

// MARK: - Session row

/// A compact row per session — tap to jump to its terminal; the bin dismisses it.
struct SessionRow: View {
    @Environment(\.vnInterfaceStyle) private var interfaceStyle
    @ObservedObject var store: EventStore
    let s: SessionActivity
    let phase: SessionPhase
    var onDismiss: (String) -> Void = { _ in }
    @State private var hovering = false
    @State private var replying = false
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            rowContent
            if replying { replyBar }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 11) {
            Button { TerminalJumper.jump(terminal: s.terminal, tty: s.tty, meta: s.termMeta ?? [:]) } label: {
              HStack(spacing: 11) {
                AgentIcon(source: s.source, size: 20)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        StatusGlyph(phase: phase)
                        Text(sessionTitle(folder: s.folder, task: s.customTitle ?? s.task))
                            .font(VNFont.ui(13, .semibold)).lineLimit(1).truncationMode(.tail)
                        if let c = s.contextTokens { ContextChip(tokens: c) }
                    }
                    if let user = s.userMessage {
                        Text("You: \(user)").font(VNFont.ui(11)).foregroundStyle(VNColor.muted)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    if let todos = s.todos, !todos.isEmpty { TodoProgress(todos: todos) }
                    brief.font(VNFont.ui(11)).lineLimit(1).truncationMode(.tail)
                    LinkChipRow(text: s.detail, imagesOnly: true)
                }
                Spacer(minLength: 8)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(s.terminal == nil)
                HStack(spacing: 5) {
                    SessionTimelineButton { store.timelineSessionID = s.id }
                    if phase == .completed, s.diffStat != nil, let cwd = s.cwd { diffButton(cwd) }
                    if let terminal = s.terminal { TerminalIcon(terminal: terminal) }
                    if TerminalControl.canReply(to: s) {
                        if hovering || replying { replyButton }
                        if phase.isBusy { interruptButton }
                    }
                }
        }
        .padding(EdgeInsets(top: interfaceStyle == .focus ? 12 : 9,
                            leading: interfaceStyle == .classic ? 18 : 12,
                            bottom: interfaceStyle == .focus ? 12 : 9,
                            trailing: interfaceStyle == .classic ? 18 : 12))
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityHint("Jumps to this session's terminal tab")
        .background(Color.white.opacity(hovering ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 9))
        .onHover { hovering = $0 }
    }

    /// The turn's changes, as `git diff HEAD` in a new terminal tab.
    private func diffButton(_ cwd: String) -> some View {
        Button {
            let quoted = "'" + cwd.replacingOccurrences(of: "'", with: "'\\''") + "'"
            TerminalLauncher.run("cd \(quoted) && git diff HEAD", purpose: "showing the diff")
        } label: {
            Image(systemName: "plus.forwardslash.minus").font(VNFont.ui(10, .semibold))
                .foregroundStyle(VNColor.paper.opacity(0.8))
                .frame(width: 26, height: 26).background(Color.white.opacity(0.07), in: Circle())
        }
        .buttonStyle(.plain)
        .help("Open this turn's diff in a terminal")
        .accessibilityLabel("Show diff")
    }

    private var replyButton: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { replying.toggle() } } label: {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(replying ? VNColor.running : VNColor.paper.opacity(0.5))
                .frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Reply to this agent")
        .accessibilityLabel("Reply")
    }

    /// Quick reply: typed into the agent's terminal, no window-hopping.
    private var replyBar: some View {
        HStack(spacing: 6) {
            TextField("Reply to \(agentName(s.source))…", text: $draft)
                .textFieldStyle(.plain).font(VNFont.ui(11.5))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.white.opacity(0.06), in: Capsule())
                .onSubmit { send(draft) }
            ForEach(["continue", "yes", "no"], id: \.self) { chip in
                Button { send(chip) } label: {
                    Text(chip).font(VNFont.ui(10.5, .medium)).foregroundStyle(VNColor.paper.opacity(0.7))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }
                .buttonStyle(PressFeedback())
            }
        }
        .padding(EdgeInsets(top: 0, leading: 49, bottom: 9, trailing: 18))
    }

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        draft = ""; replying = false
        Task { _ = await TerminalControl.send(t, to: s, allowActiveTab: true) }
    }

    private var interruptButton: some View {
        InterruptButton(running: phase == .working) {
            Task { _ = await TerminalControl.interrupt(s) }
        }
    }

    /// Phase and detail share the same interpretation as the single-session card.
    private var brief: Text {
        let status = Text(phase.statusText(event: s.event, tool: s.tool)).foregroundStyle(phase.tint)
        if phase == .completed, let d = s.diffStat, d.count == 3 {
            return status + Text(" · \(d[0]) file\(d[0] == 1 ? "" : "s") ").foregroundStyle(VNColor.muted)
                + Text("+\(d[1]) ").foregroundStyle(VNColor.go)
                + Text("−\(d[2])").foregroundStyle(VNColor.stop)
        }
        guard phase == .working || phase == .completed || phase == .failed,
              let detail = s.detail?.components(separatedBy: "\n").first, !detail.isEmpty else { return status }
        return status + Text(" · " + String(detail.prefix(100))).foregroundStyle(VNColor.faint)
    }
}

// MARK: - Session controls (reply, panic, git)

/// Branch chip: `⎇ main` with an amber dot when the tree is dirty.
struct GitChip: View {
    let branch: String?
    let dirty: Bool
    var body: some View {
        if let branch {
            HStack(spacing: 3) {
                Text("⎇ \(branch)").font(VNFont.sysMono(9.5, .medium))
                    .foregroundStyle(VNColor.paper.opacity(0.5))
                    .lineLimit(1)
                if dirty { Circle().fill(VNColor.amber).frame(width: 4, height: 4) }
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.white.opacity(0.05), in: Capsule())
        }
    }
}

/// Compact token count: 950 → "950", 12_400 → "12k", 1_300_000 → "1.3M".
func kFmt(_ n: Int) -> String {
    if n < 1000 { return "\(n)" }
    if n < 1_000_000 { return "\(n / 1000)k" }
    return String(format: "%.1fM", Double(n) / 1_000_000)
}

/// Claude's TodoWrite checklist: "3/7" progress plus each step.
struct TodoList: View {
    let todos: [VNTodo]
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("TASKS  \(todos.filter { $0.status == "completed" }.count)/\(todos.count)")
                .font(VNFont.sysMono(9.5, .semibold)).foregroundStyle(VNColor.faint)
            ForEach(Array(todos.prefix(8).enumerated()), id: \.offset) { _, t in
                HStack(spacing: 6) {
                    Image(systemName: t.status == "completed" ? "checkmark.circle.fill"
                                    : t.status == "in_progress" ? "circle.dotted" : "circle")
                        .font(VNFont.ui(9.5))
                        .foregroundStyle(t.status == "completed" ? VNColor.go
                                       : t.status == "in_progress" ? VNColor.running : VNColor.faint)
                    Text(t.content).font(VNFont.ui(11)).lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(t.status == "completed" ? VNColor.muted : VNColor.text)
                }
            }
        }
    }
}

/// Round stop control: a ring with a rounded square inside. Quiet until hovered,
/// then red; brighter while the agent is actually working.
private struct InterruptButton: View {
    let running: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let tint = hovering ? VNColor.stop : VNColor.paper.opacity(running ? 0.6 : 0.3)
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(tint, lineWidth: 1.5)
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(tint).frame(width: 8, height: 8)
            }
            .frame(width: 22, height: 22)
            .background(hovering ? VNColor.stop.opacity(0.14) : .clear, in: Circle())
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Interrupt agent")
        .help("Interrupt (Esc)")
    }
}

// MARK: - Todo progress, context fill

/// TodoWrite as a slim bar: done/total, then what it's on now.
struct TodoProgress: View {
    let todos: [VNTodo]
    var body: some View {
        let done = todos.filter { $0.status == "completed" }.count
        let now = todos.first { $0.status == "in_progress" }?.content
        HStack(spacing: 7) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(VNColor.running)
                        .frame(width: g.size.width * CGFloat(done) / CGFloat(max(1, todos.count)))
                }
            }
            .frame(width: 54, height: 4)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: done)
            Text("\(done)/\(todos.count)").font(VNFont.sysMono(10, .semibold)).foregroundStyle(VNColor.running)
            if let now { Text(now).font(VNFont.ui(11)).foregroundStyle(VNColor.muted).lineLimit(1).truncationMode(.tail) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(todos.count) tasks done" + (now.map { ", now \($0)" } ?? ""))
    }
}

/// How full the context window is — only shown once it matters (70%+), amber from 85%.
struct ContextChip: View {
    let tokens: Int
    // ponytail: window guessed from usage (200k, or 1M once past it); read the model's real limit if agents ever report it
    static func percent(_ tokens: Int) -> Int { min(100, tokens * 100 / (tokens > 200_000 ? 1_000_000 : 200_000)) }
    var body: some View {
        let pct = Self.percent(tokens)
        if pct >= 70 {
            let tint = pct >= 85 ? VNColor.amber : VNColor.paper.opacity(0.5)
            Text("ctx \(pct)%").font(VNFont.sysMono(9.5, .semibold)).foregroundStyle(tint)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(tint.opacity(0.14), in: Capsule())
                .help(pct >= 85 ? "Context nearly full: consider /compact" : "Context window \(pct)% full")
        }
    }
}
