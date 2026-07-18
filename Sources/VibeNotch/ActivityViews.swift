import SwiftUI
import VibeNotchCore

/// Shows what active agent sessions are doing right now (or an idle pill).
/// One session → detail card; several + hover → the SESSIONS list.
struct ActivityCard: View {
    let sessions: [SessionActivity]
    let full: Bool

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
                PillCluster(source: s.source, model: s.model, terminal: s.terminal)
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
            VStack(alignment: .leading, spacing: 13) {
                ForEach(sessions) { s in SessionRow(s: s) }
            }
            .padding(.top, 11)
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
        default: Circle().fill(VNColor.faint).frame(width: 5, height: 5)
        }
    }

    private var label: String {
        switch s.event {
        case "PreToolUse": return "Running \(s.tool ?? "tool")"
        case "PostToolUse": return s.tool ?? "Output"
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

/// A compact row per session in the multi-session list — tap to jump to its terminal.
struct SessionRow: View {
    let s: SessionActivity

    var body: some View {
        Button { TerminalJumper.jump(s.terminal) } label: {
            HStack(alignment: .top, spacing: 9) {
                AgentIcon(source: s.source, size: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sessionTitle(folder: s.folder, task: s.task))
                        .font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    if let user = s.userMessage {
                        Text("You: \(user)").font(.system(size: 10.5)).foregroundStyle(VNColor.muted)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    Text(brief).font(.system(size: 10.5)).foregroundStyle(VNColor.faint).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 8)
                PillCluster(source: s.source, model: s.model, terminal: s.terminal,
                            showJump: false, age: s.updatedAt)
            }
            .padding(.vertical, 4).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var brief: String {
        switch s.event {
        case "PreToolUse": return "\(s.tool ?? "Running") \(s.detail ?? "")"
        case "Notification": return "Waiting for input"
        case "Stop": return s.detail.map { String($0.prefix(80)) } ?? "Finished"
        case "UserPromptSubmit": return "Thinking…"
        default: return "Working…"
        }
    }
}
