import SwiftUI
import VibeNotchCore

/// Shows what active agent sessions are doing right now (or an idle pill).
/// One session → detail card; several + hover → the SESSIONS list.
struct ActivityCard: View {
    @ObservedObject var store: EventStore
    let sessions: [SessionActivity]
    let full: Bool
    var onDismiss: (String) -> Void = { _ in }

    var body: some View {
        if sessions.isEmpty {
            idlePill
        } else if sessions.count > 1 && full {
            listCard
        } else {
            singleCard(sessions[0])
        }
    }

    // MARK: Idle

    private var idlePill: some View {
        HStack(spacing: 12) {
            EvolvedInvader(px: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("vibe-notch").font(VNFont.ui(13, .semibold))
                Text(AgentConnections.anyConnected ? "no active sessions" : "not connected")
                    .font(VNFont.ui(11)).foregroundStyle(VNColor.muted)
            }
            Spacer(minLength: 12)
        }
        .padding(EdgeInsets(top: 4, leading: 20, bottom: 10, trailing: 20))
        .frame(width: 260)
    }

    // MARK: Single session

    private func singleCard(_ s: SessionActivity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                AgentIcon(source: s.source, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(sessionTitle(folder: s.folder, task: s.task))
                            .font(VNFont.ui(12.5, .semibold)).lineLimit(1).truncationMode(.tail)
                        GitChip(branch: s.gitBranch, dirty: s.gitDirty)
                    }
                    if let user = s.userMessage {
                        Text("You: \(user)").font(VNFont.ui(10.5)).foregroundStyle(VNColor.muted)
                            .lineLimit(full ? 3 : 1).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                PillCluster(source: s.source, terminal: s.terminal, tty: s.tty, meta: s.termMeta ?? [:])
                if full {
                    Button("Controls") { store.controlSessionID = s.id }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            SessionStatusLine(s: s, full: full)
            if full, store.controlSessionID == s.id { SessionControls(store: store, session: s).id(s.id) }

        }
        .padding(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
        .frame(width: CGFloat(VNSettings.panelWidth) - 20, alignment: .leading)
            }

    // MARK: Session list

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sessionsHeader
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, s in
                        SessionRow(s: s, onDismiss: onDismiss,
                                   replying: store.controlSessionID == s.sessionId) { id in
                            store.controlSessionID = store.controlSessionID == id ? nil : id
                        }
                        if store.controlSessionID == s.sessionId {
                            SessionControls(store: store, session: s)
                                .padding(.horizontal, 10).padding(.bottom, 8)
                        }
                        if index < sessions.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.055))
                                .frame(height: 1).padding(.leading, 40)
                        }
                    }
                }
            .background(Color.white.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06)))
            .padding(.top, 6)
        }
        .padding(EdgeInsets(top: 2, leading: 16, bottom: 10, trailing: 16))
        .frame(width: CGFloat(VNSettings.panelWidth), alignment: .leading)
    }

    private var sessionsHeader: some View {
        HStack(spacing: 9) {
            Text("LIVE AGENTS").font(VNFont.sysMono(10.5, .semibold)).tracking(1.4)
                .foregroundStyle(VNColor.paper.opacity(0.55))
            Spacer(minLength: 8)
            ForEach(metrics, id: \.label) { metric in
                HStack(spacing: 4) {
                    if let color = metric.color { Circle().fill(color).frame(width: 5, height: 5) }
                    Text(metric.label).font(VNFont.sysMono(9.5, .medium))
                        .foregroundStyle(VNColor.paper.opacity(metric.color == nil ? 0.3 : 0.42))
                }
            }
        }
        .padding(.bottom, 2)
    }

    private var metrics: [(label: String, color: Color?)] {
        let running = sessions.filter { ["PreToolUse", "PostToolUse", "UserPromptSubmit"].contains($0.event) }.count
        let waiting = sessions.filter { $0.event == "Notification" }.count
        let done = sessions.filter { $0.event == "Stop" }.count
        var out: [(String, Color?)] = [("\(sessions.count) agent\(sessions.count == 1 ? "" : "s")", nil)]
        if waiting > 0 { out.append(("\(waiting) waiting", VNColor.amber)) }
        if running > 0 { out.append(("\(running) running", VNColor.running)) }
        if done > 0 { out.append(("\(done) done", VNColor.go)) }
        return out
    }
}

// MARK: - Status line (spinner/icon + label + terminal block)

/// The "what is it doing" line: status glyph + label, and the real terminal
/// text (command, output, or the agent's message) in a mono block.
struct SessionStatusLine: View {
    let s: SessionActivity
    let full: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                icon
                Text(label).font(VNFont.ui(11.5, .medium)).foregroundStyle(labelColor)
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

    @ViewBuilder private var icon: some View {
        switch s.event {
        case "PreToolUse", "PostToolUse", "UserPromptSubmit", "PreCompact": PixelRingSpinner(color: VNColor.running)
        case "Notification": Image(systemName: "hourglass").font(VNFont.ui(10)).foregroundStyle(VNColor.amber)
        case "Stop": Image(systemName: "checkmark.circle.fill").font(VNFont.ui(10)).foregroundStyle(VNColor.go)
        case "PostToolUseFailure", "StopFailure":
            Image(systemName: "xmark.circle.fill").font(VNFont.ui(10)).foregroundStyle(VNColor.stop)
        default: Circle().fill(VNColor.faint).frame(width: 5, height: 5)
        }
    }

    private var label: String {
        switch s.event {
        case "PreToolUse": return "Running \(s.tool ?? "tool")"
        case "PostToolUse": return s.tool ?? "Output"
        case "PostToolUseFailure": return "\(s.tool ?? "Tool") failed"
        case "StopFailure": return "Failed"
        case "Notification": return s.detail ?? "Waiting for input"
        case "Stop": return "Finished"
        case "UserPromptSubmit": return "Thinking…"
        case "PreCompact": return "Compacting context…"
        default: return "Working…"
        }
    }

    private var labelColor: Color {
        switch s.event {
        case "Notification": return VNColor.amber
        case "Stop": return VNColor.go
        case "PostToolUseFailure", "StopFailure": return VNColor.stop
        default: return VNColor.text
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

/// Stable row actions; selecting the main content opens this session’s controls.
struct SessionRow: View {
    let s: SessionActivity
    var onDismiss: (String) -> Void = { _ in }
    var replying = false
    var onReply: (String) -> Void = { _ in }
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Button { onReply(s.sessionId) } label: {
              HStack(spacing: 11) {
                AgentIcon(source: s.source, size: 20)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        StatusGlyph(event: s.event)
                        Text(sessionTitle(folder: s.folder, task: s.task))
                            .font(VNFont.ui(13, .semibold)).lineLimit(1).truncationMode(.tail)
                    }
                    if let user = s.userMessage {
                        Text("You: \(user)").font(VNFont.ui(11)).foregroundStyle(VNColor.muted)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    if let todos = s.todos, !todos.isEmpty {
                        let done = todos.filter { $0.status == "completed" }.count
                        let now = todos.first { $0.status == "in_progress" }?.content
                        Text("☑ \(done)/\(todos.count)" + (now.map { " · \($0)" } ?? ""))
                            .font(VNFont.ui(11)).foregroundStyle(VNColor.running).lineLimit(1).truncationMode(.tail)
                    }
                    brief.font(VNFont.ui(11)).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 8)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
                HStack(spacing: 5) {
                    PillCluster(source: s.source, terminal: s.terminal, tty: s.tty, meta: s.termMeta ?? [:],
                                showJump: false)
                    Group {
                        replyButton
                        JumpPill(terminal: s.terminal, tty: s.tty, meta: s.termMeta ?? [:])
                        binButton
                    }
                }
        }
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityHint("Opens controls for this session")
        .background(Color.white.opacity(hovering ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 9))
        .onHover { hovering = $0 }
    }

    private var replyButton: some View {
        Button { onReply(s.sessionId) } label: {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(replying ? VNColor.go : VNColor.muted)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel("Session controls").help("Reply, model, interrupt and resume")
    }

    private var binButton: some View {
        Button { onDismiss(s.sessionId) } label: {
            Image(systemName: "archivebox")
                .font(VNFont.ui(11, .medium))
                .foregroundStyle(VNColor.muted)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Archive session")
        .help("Archive session")
    }

    /// Activity line — tool name in blue, arguments/reply in grey (inspo style).
    private var brief: Text {
        switch s.event {
        case "PreToolUse", "PostToolUse":
            return Text(s.tool ?? "Running").foregroundStyle(VNColor.running)
                 + Text(" \(s.detail?.components(separatedBy: "\n").first ?? "")").foregroundStyle(VNColor.faint)
        case "Notification":
            return Text("Waiting for input").foregroundStyle(VNColor.amber)
        case "PostToolUseFailure":
            return Text("\(s.tool ?? "Tool") failed").foregroundStyle(VNColor.stop)
        case "StopFailure":
            return Text("Failed").foregroundStyle(VNColor.stop)
        case "Stop":
            return Text(s.detail.map { String($0.prefix(80)) } ?? "Finished").foregroundStyle(VNColor.faint)
        case "UserPromptSubmit":
            return Text("Thinking…").foregroundStyle(VNColor.faint)
        default:
            return Text("Working…").foregroundStyle(VNColor.faint)
        }
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
