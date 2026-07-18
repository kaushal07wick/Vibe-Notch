import SwiftUI
import VibeNotchCore

/// Shows what active agent sessions are doing right now (or an idle pill).
/// One session → detail card; several + hover → the SESSIONS list.
struct ActivityCard: View {
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
            PixelInvader(color: VNColor.invader, px: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("vibe-notch").font(.system(size: 13, weight: .semibold))
                Text(AgentConnections.anyConnected ? "no active sessions" : "not connected")
                    .font(.system(size: 11)).foregroundStyle(VNColor.muted)
            }
            Spacer(minLength: 12)
        }
        .padding(EdgeInsets(top: 7, leading: 16, bottom: 9, trailing: 16))
        .frame(width: 300)
    }

    // MARK: Single session

    private func singleCard(_ s: SessionActivity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                AgentIcon(source: s.source)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sessionTitle(folder: s.folder, task: s.task))
                        .font(.system(size: 13.5, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    if let user = s.userMessage {
                        Text("You: \(user)").font(.system(size: 11)).foregroundStyle(VNColor.muted)
                            .lineLimit(full ? 3 : 1).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                PillCluster(source: s.source, model: s.model, terminal: s.terminal, tty: s.tty)
            }
            SessionStatusLine(s: s, full: full)
        }
        .padding(EdgeInsets(top: 6, leading: 15, bottom: 9, trailing: 15))
        .frame(width: 540, alignment: .leading)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: full)
    }

    // MARK: Session list

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sessionsHeader
            VStack(alignment: .leading, spacing: 9) {
                ForEach(sessions) { s in SessionRow(s: s, onDismiss: onDismiss) }
            }
            .padding(.top, 9)
        }
        .padding(EdgeInsets(top: 9, leading: 18, bottom: 12, trailing: 18))
        .frame(width: 540, alignment: .leading)
    }

    private var sessionsHeader: some View {
        HStack(spacing: 9) {
            Text("SESSIONS").font(VNFont.sysMono(10.5, .semibold)).tracking(1.4)
                .foregroundStyle(VNColor.paper.opacity(0.55))
            Spacer(minLength: 8)
            ForEach(metrics, id: \.label) { metric in
                HStack(spacing: 4) {
                    if let color = metric.color { Circle().fill(color).frame(width: 5.5, height: 5.5) }
                    Text(metric.label).font(VNFont.sysMono(10.5, .semibold))
                        .foregroundStyle(VNColor.paper.opacity(metric.color == nil ? 0.34 : 0.48))
                }
            }
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.055)).frame(height: 1) }
    }

    private var metrics: [(label: String, color: Color?)] {
        let running = sessions.filter { ["PreToolUse", "PostToolUse", "UserPromptSubmit"].contains($0.event) }.count
        let waiting = sessions.filter { $0.event == "Notification" }.count
        let done = sessions.filter { $0.event == "Stop" }.count
        var out: [(String, Color?)] = [("\(sessions.count) Sessions", nil)]
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
                Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(labelColor)
                Spacer(minLength: 0)
                if s.subagents > 0 {
                    Text("\(s.subagents) subagent\(s.subagents == 1 ? "" : "s")")
                        .font(VNFont.sysMono(10, .medium)).foregroundStyle(VNColor.running.opacity(0.85))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(VNColor.running.opacity(0.12), in: Capsule())
                }
            }
            if let detail = s.detail, !detail.isEmpty, s.event != "Notification" {
                TerminalBlock(text: detail, prompt: s.event == "PreToolUse", lines: full ? 8 : 3)
            }
        }
    }

    @ViewBuilder private var icon: some View {
        switch s.event {
        case "PreToolUse", "PostToolUse", "UserPromptSubmit": AsciiSpinner(color: VNColor.running)
        case "Notification": Image(systemName: "hourglass").font(.system(size: 10)).foregroundStyle(VNColor.amber)
        case "Stop": Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(VNColor.go)
        case "PostToolUseFailure", "StopFailure":
            Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(VNColor.stop)
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
            .font(VNFont.mono(11))
            .foregroundStyle(Color(hex: 0xC8CDD4))
            .lineLimit(lines).truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(VNColor.ink2, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(VNColor.hair))
    }
}

// MARK: - Session row

/// A compact row per session in the multi-session list — tap to jump to its
/// terminal. Hover highlights the row and reveals a bin button to dismiss it.
struct SessionRow: View {
    let s: SessionActivity
    var onDismiss: (String) -> Void = { _ in }
    @State private var hovering = false

    var body: some View {
        Button { TerminalJumper.jump(terminal: s.terminal, tty: s.tty) } label: {
            HStack(alignment: .top, spacing: 9) {
                AgentIcon(source: s.source, size: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sessionTitle(folder: s.folder, task: s.task))
                        .font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    if let user = s.userMessage {
                        Text("You: \(user)").font(.system(size: 10.5)).foregroundStyle(VNColor.muted)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    brief.font(.system(size: 10.5)).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    // pills stay on hover; only the age slot becomes the archive button
                    PillCluster(source: s.source, model: s.model, terminal: s.terminal, tty: s.tty,
                                showJump: false, age: hovering ? nil : s.updatedAt)
                    if hovering { binButton }
                }
            }
            .padding(EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(hovering ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(hovering ? 0.08 : 0)))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    }

    private var binButton: some View {
        Button { onDismiss(s.sessionId) } label: {
            Image(systemName: "archivebox")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(VNColor.muted)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
