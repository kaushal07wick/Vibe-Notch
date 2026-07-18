import SwiftUI
import VibeNotchCore

// Content only — DynamicNotchKit draws the notch shape, background, and morph.
// Matches Vibe Island: animated pixel invader in compact, wide cards on expand.

// MARK: - Expanded

struct ExpandedContent: View {
    @ObservedObject var store: EventStore

    var body: some View {
        ZStack {
            currentCard
                .id(stateKey)
                .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity),
                                        removal: .opacity))
        }
        .foregroundStyle(VNColor.text)
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: stateKey)
        .overlay(alignment: .bottom) { GlowSeam(style: seam) }
    }

    private var stateKey: String {
        if let a = store.pending.first { return "approval-\(a.id)" }
        if let f = store.flash { return "flash-\(f.rawValue)" }
        let active = store.activeSessions
        guard let s = active.first else { return "idle" }
        return "act-\(active.count)-\(s.id)-\(s.event)"
    }

    @ViewBuilder private var currentCard: some View {
        if let approval = store.pending.first {
            ApprovalCard(approval: approval, store: store, queued: store.pending.count - 1)
        } else if let flash = store.flash {
            FlashPill(decision: flash)
        } else {
            ActivityCard(sessions: store.activeSessions, full: store.hovering)
        }
    }

    private var seam: SeamStyle {
        if let a = store.pending.first { return SeamStyle(color: VNColor.agent(a.inbound.source), pulses: true) }
        if let f = store.flash { return SeamStyle(color: f == .allow ? VNColor.go : VNColor.stop, pulses: false) }
        if let s = store.activeSession {
            switch s.event {
            case "Notification": return SeamStyle(color: VNColor.amber, pulses: true)
            case "Stop": return SeamStyle(color: VNColor.go, pulses: false)
            default: return SeamStyle(color: VNColor.agent(s.source), pulses: false)
            }
        }
        return SeamStyle(color: VNColor.faint, pulses: false, dim: true)
    }
}

// MARK: - Compact flanks

struct CompactLeading: View {
    @ObservedObject var store: EventStore
    var body: some View {
        HStack(spacing: 6) {
            if activeAgents.isEmpty {
                PixelInvader(color: VNColor.invader) // idle mascot
            } else {
                ForEach(activeAgents, id: \.self) { AgentIcon(source: $0, size: 15) }
            }
        }
        .padding(.leading, 11).padding(.trailing, 6)
    }
    /// Distinct agents that have a live session, most-recent first.
    private var activeAgents: [String] {
        var seen = Set<String>(); var out: [String] = []
        for s in store.activeSessions where !seen.contains(s.source) { seen.insert(s.source); out.append(s.source) }
        return out
    }
}

struct CompactTrailing: View {
    @ObservedObject var store: EventStore
    var body: some View {
        Group {
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(VNColor.text)
            } else {
                Circle().fill(VNColor.faint).frame(width: 5, height: 5)
            }
        }
        .padding(.trailing, 13).padding(.leading, 6)
    }
    private var count: Int { max(store.pending.count, store.activeSessions.count) }
}

// MARK: - Cards

private struct ApprovalCard: View {
    let approval: PendingApproval
    @ObservedObject var store: EventStore
    let queued: Int
    private var i: VNInbound { approval.inbound }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                AgentIcon(source: i.source)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText).font(.system(size: 13.5, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    if let user = i.userMessage {
                        Text("You: \(user)").font(.system(size: 11)).foregroundStyle(VNColor.muted)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    AgentPill(source: i.source)
                    if let m = i.model { ModelPill(model: m) }
                    if let term = i.terminal { TermPill(name: term) }
                    JumpPill(terminal: i.terminal)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(VNColor.amber)
                Text(i.tool ?? "Tool").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(VNColor.amber)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 5) {
                (Text("$ ").foregroundStyle(VNColor.amber) + Text(i.detail ?? "").foregroundStyle(Color(hex: 0xE7E8E4)))
                    .font(VNFont.mono(11.5)).lineLimit(3).truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                if let desc = i.commandDescription {
                    Text(desc).font(.system(size: 11)).foregroundStyle(VNColor.muted).lineLimit(1)
                }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(VNColor.ink2, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(VNColor.hair))
            HStack(spacing: 8) {
                WideButton(title: "Deny", kind: .deny) { store.resolve(approval, .deny) }
                WideButton(title: "Allow Once", kind: .primary) { store.resolve(approval, .allow) }
                WideButton(title: "Always Allow", kind: .always) { store.resolve(approval, .allow) }
                WideButton(title: "Bypass", kind: .danger) { store.resolve(approval, .allow) }
            }
            if queued > 0 {
                Text("Show all \(queued + 1) sessions")
                    .font(.system(size: 11)).foregroundStyle(VNColor.faint)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, 1)
            }
        }
        .padding(EdgeInsets(top: 6, leading: 15, bottom: 10, trailing: 15))
        .frame(width: 560)
    }

    private var titleText: String {
        let folder = (i.cwd as NSString?)?.lastPathComponent ?? "session"
        if let task = i.title, !task.isEmpty { return "\(folder) · \(task)" }
        return folder
    }
}

/// Shows what active agent sessions are doing right now (or an idle pill).
private struct ActivityCard: View {
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

    private var idlePill: some View {
        HStack(spacing: 12) {
            PixelInvader(color: VNColor.invader, px: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("vibe-notch").font(.system(size: 13, weight: .semibold))
                Text(ClaudeInstaller.isConnected ? "no active sessions" : "not connected")
                    .font(.system(size: 11)).foregroundStyle(VNColor.muted)
            }
            Spacer(minLength: 12)
        }
        .padding(EdgeInsets(top: 7, leading: 16, bottom: 9, trailing: 16))
        .frame(width: 300)
    }

    private func singleCard(_ s: SessionActivity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            StatsHeader(elapsed: elapsedString(since: s.startedAt), activeCount: sessions.count)
            HStack(alignment: .top, spacing: 8) {
                AgentIcon(source: s.source)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText(s)).font(.system(size: 13.5, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    if let user = s.userMessage {
                        Text("You: \(user)").font(.system(size: 11)).foregroundStyle(VNColor.muted)
                            .lineLimit(full ? 3 : 1).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    AgentPill(source: s.source)
                    if let m = s.model { ModelPill(model: m) }
                    if let term = s.terminal { TermPill(name: term) }
                    JumpPill(terminal: s.terminal)
                }
            }
            activityLine(s)
        }
        .padding(EdgeInsets(top: 6, leading: 15, bottom: 9, trailing: 15))
        .frame(width: 560, alignment: .leading)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: full)
    }

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            StatsHeader(elapsed: "\(sessions.count) sessions", activeCount: sessions.count)
            ForEach(sessions) { s in
                SessionRow(s: s)
                if s.id != sessions.last?.id { Divider().overlay(VNColor.hair) }
            }
        }
        .padding(EdgeInsets(top: 6, leading: 14, bottom: 9, trailing: 14))
        .frame(width: 560, alignment: .leading)
    }

    private func titleText(_ s: SessionActivity) -> String {
        let folder = s.folder ?? "session"
        if let task = s.task, !task.isEmpty { return "\(folder) · \(task)" }
        return folder
    }

    @ViewBuilder private func activityLine(_ s: SessionActivity) -> some View {
        HStack(spacing: 6) {
            switch s.event {
            case "PreToolUse":
                Image(systemName: "gearshape.fill").font(.system(size: 10)).foregroundStyle(VNColor.invader)
                Text("Running \(s.tool ?? "tool")").font(.system(size: 11.5, weight: .medium))
                if let d = s.detail {
                    Text(d).font(VNFont.mono(11)).foregroundStyle(VNColor.muted).lineLimit(1).truncationMode(.middle)
                }
            case "Notification":
                Image(systemName: "hourglass").font(.system(size: 10)).foregroundStyle(VNColor.amber)
                Text(s.detail ?? "Waiting for input").font(.system(size: 11.5)).foregroundStyle(VNColor.amber).lineLimit(1)
            case "Stop":
                Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(VNColor.go)
                Text(s.detail ?? "Finished").font(.system(size: 11.5)).foregroundStyle(VNColor.muted)
                    .lineLimit(full ? 5 : 1).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
            case "UserPromptSubmit":
                Image(systemName: "ellipsis.circle").font(.system(size: 10)).foregroundStyle(VNColor.muted)
                Text("Thinking…").font(.system(size: 11.5)).foregroundStyle(VNColor.muted)
            default:
                Circle().fill(VNColor.faint).frame(width: 5, height: 5)
                Text(s.detail ?? "Working…").font(.system(size: 11.5)).foregroundStyle(VNColor.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A compact row per session in the multi-session list — tap to jump to its terminal.
private struct SessionRow: View {
    let s: SessionActivity
    var body: some View {
        Button { TerminalJumper.jump(s.terminal) } label: {
            HStack(alignment: .top, spacing: 9) {
                AgentIcon(source: s.source, size: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(titleText).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    if let user = s.userMessage {
                        Text("You: \(user)").font(.system(size: 10.5)).foregroundStyle(VNColor.muted)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    Text(brief).font(.system(size: 10.5)).foregroundStyle(VNColor.faint).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    AgentPill(source: s.source)
                    if let m = s.model { ModelPill(model: m) }
                    if let t = s.terminal { TermPill(name: t) }
                }
            }
            .padding(.vertical, 4).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    private var titleText: String {
        let folder = s.folder ?? "session"
        if let task = s.task, !task.isEmpty { return "\(folder) · \(task)" }
        return folder
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

private struct StatsHeader: View {
    let elapsed: String
    let activeCount: Int
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "clock").font(.system(size: 9)).foregroundStyle(VNColor.faint)
            Text(elapsed).font(VNFont.mono(10)).foregroundStyle(VNColor.muted)
            Text("·").font(VNFont.mono(10)).foregroundStyle(VNColor.faint)
            Text("\(activeCount) active").font(VNFont.mono(10))
                .foregroundStyle(activeCount > 1 ? VNColor.go : VNColor.muted)
            Spacer(minLength: 0)
        }
    }
}

private func elapsedString(since date: Date) -> String {
    let s = max(0, Int(Date().timeIntervalSince(date)))
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m" }
    return "\(s / 3600)h \((s % 3600) / 60)m"
}

private struct FlashPill: View {
    let decision: VNDecision
    @State private var shown = false
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: decision == .allow ? "checkmark" : "xmark")
                .font(.system(size: 11, weight: .bold)).scaleEffect(shown ? 1 : 0.3).opacity(shown ? 1 : 0)
            Text(decision == .allow ? "Approved" : "Denied").font(.system(size: 12.5, weight: .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(decision == .allow ? VNColor.go : VNColor.stop)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .frame(width: 260, alignment: .leading)
        .onAppear { withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { shown = true } }
    }
}

// MARK: - Pills, buttons

private struct AgentPill: View {
    let source: String
    var body: some View {
        Text(agentName(source))
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(darkText ? Color(hex: 0x1A120E) : .white)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(VNColor.agent(source), in: RoundedRectangle(cornerRadius: 6))
    }
    // warm/light agent hues read better with dark text
    private var darkText: Bool { source == "claude" || source == "opencode" }
}

private struct ModelPill: View {
    let model: String
    var body: some View {
        Text(model)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(VNColor.text.opacity(0.8))
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(VNColor.ink2, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Per-agent brand glyph — Claude clay sparkle, Codex blue mark.
struct AgentIcon: View {
    let source: String
    var size: CGFloat = 16
    var body: some View {
        Image(systemName: source == "codex" ? "asterisk" : "sparkle")
            .font(.system(size: size * 0.85, weight: .semibold))
            .foregroundStyle(VNColor.agent(source))
    }
}

private struct TermPill: View {
    let name: String
    var body: some View {
        Text(name)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(VNColor.text.opacity(0.8))
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(VNColor.ink2, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct WideButton: View {
    enum Kind { case deny, primary, always, danger }
    let title: String
    let kind: Kind
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(bg, in: RoundedRectangle(cornerRadius: 9))
        .foregroundStyle(fg)
    }
    private var bg: Color {
        switch kind {
        case .deny: VNColor.ink2
        case .primary: .white
        case .always: VNColor.invader
        case .danger: Color(hex: 0xB0413F)
        }
    }
    private var fg: Color { switch kind { case .primary: .black; default: .white } }
}

private struct JumpPill: View {
    let terminal: String?
    var body: some View {
        Button { TerminalJumper.jump(terminal) } label: {
            HStack(spacing: 3) {
                Text("^G").font(VNFont.mono(9.5))
                Image(systemName: "arrow.up.forward").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Color(hex: 0x6FD3E0))
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .background(Color(hex: 0x123238), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Seam

struct SeamStyle { var color: Color; var pulses: Bool; var dim: Bool = false }

private struct GlowSeam: View {
    let style: SeamStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        Capsule().fill(style.color)
            .frame(height: 2).shadow(color: style.color, radius: 5)
            .padding(.horizontal, 30).padding(.bottom, 1)
            .opacity(style.dim ? 0.45 : (style.pulses ? (on ? 1 : 0.4) : 0.9))
            .onAppear {
                if style.pulses && !reduceMotion {
                    withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { on = true }
                }
            }
    }
}

// MARK: - Animated pixel invader (the ASCII mascot)

struct PixelInvader: View {
    var color: Color
    var px: CGFloat = 2.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let frameA = [
        "..X.....X..",
        "...X...X...",
        "..XXXXXXX..",
        ".XX.XXX.XX.",
        "XXXXXXXXXXX",
        "X.XXXXXXX.X",
        "X.X.....X.X",
        "...XX.XX...",
    ]
    private static let frameB = [
        "..X.....X..",
        "X..X...X..X",
        "X.XXXXXXX.X",
        "XXX.XXX.XXX",
        "XXXXXXXXXXX",
        ".XXXXXXXXX.",
        "..X.....X..",
        ".X.......X.",
    ]

    private func cells(_ rows: [String]) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch == "X" { out.append((x, y)) }
        }
        return out
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.45)) { ctx in
            let useA = reduceMotion || Int(ctx.date.timeIntervalSinceReferenceDate / 0.45) % 2 == 0
            let f = cells(useA ? Self.frameA : Self.frameB)
            Canvas { c, _ in
                for (x, y) in f {
                    c.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px)),
                           with: .color(color))
                }
            }
            .frame(width: 11 * px, height: 8 * px)
        }
    }
}
