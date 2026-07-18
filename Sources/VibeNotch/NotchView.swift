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
        if store.lastNotification != nil { return "notif" }
        return "status"
    }

    @ViewBuilder private var currentCard: some View {
        if let approval = store.pending.first {
            ApprovalCard(approval: approval, store: store, queued: store.pending.count - 1)
        } else if let flash = store.flash {
            FlashPill(decision: flash)
        } else if let note = store.lastNotification {
            NotificationCard(inbound: note, full: store.hovering)
        } else {
            StatusPanel(store: store)
        }
    }

    private var seam: SeamStyle {
        if let a = store.pending.first { return SeamStyle(color: VNColor.agent(a.inbound.source), pulses: true) }
        if let f = store.flash { return SeamStyle(color: f == .allow ? VNColor.go : VNColor.stop, pulses: false) }
        if let n = store.lastNotification { return SeamStyle(color: VNColor.agent(n.source), pulses: false) }
        return SeamStyle(color: VNColor.faint, pulses: false, dim: true)
    }
}

// MARK: - Compact flanks

struct CompactLeading: View {
    @ObservedObject var store: EventStore
    var body: some View {
        HStack(spacing: 5) {
            PixelInvader(color: VNColor.invader)
            PixelInvader(color: VNColor.invader.opacity(0.65))
        }
        .padding(.leading, 11).padding(.trailing, 6)
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
    private var count: Int { store.pending.count + (store.lastNotification != nil ? 1 : 0) }
}

// MARK: - Cards

private struct ApprovalCard: View {
    let approval: PendingApproval
    @ObservedObject var store: EventStore
    let queued: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                PixelInvader(color: VNColor.invader, px: 2)
                Text(folder).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 8)
                AgentPill(source: approval.inbound.source)
                if let term = approval.inbound.terminal { TermPill(name: term) }
            }
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(VNColor.amber)
                Text(approval.inbound.tool ?? "Tool")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(VNColor.amber)
                Text(approval.inbound.detail ?? "")
                    .font(VNFont.mono(11.5)).foregroundStyle(Color(hex: 0xE7E8E4))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                WideButton(title: "Deny", kind: .deny) { store.resolve(approval, .deny) }
                WideButton(title: "Allow Once", kind: .primary) { store.resolve(approval, .allow) }
                WideButton(title: "Bypass", kind: .danger) { store.resolve(approval, .allow) }
            }
            if queued > 0 {
                Text("Show all \(queued + 1) requests")
                    .font(.system(size: 11)).foregroundStyle(VNColor.faint)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(EdgeInsets(top: 6, leading: 15, bottom: 10, trailing: 15))
        .frame(width: 540)
    }

    private var folder: String { (approval.inbound.cwd as NSString?)?.lastPathComponent ?? "session" }
}

private struct NotificationCard: View {
    let inbound: VNInbound
    let full: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                PixelInvader(color: VNColor.invader, px: 2)
                Text(titleText).font(.system(size: 13.5, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                AgentPill(source: inbound.source)
                if let term = inbound.terminal { TermPill(name: term) }
            }
            if let body = inbound.detail, !body.isEmpty {
                Text(body)
                    .font(.system(size: 11.5)).foregroundStyle(VNColor.muted)
                    .lineLimit(full ? 12 : 2).truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(EdgeInsets(top: 6, leading: 15, bottom: 9, trailing: 15))
        .frame(width: 540, alignment: .leading)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: full)
    }
    private var titleText: String {
        let folder = (inbound.cwd as NSString?)?.lastPathComponent
        if let f = folder, let t = inbound.title { return "\(f) · \(t)" }
        return inbound.title ?? (inbound.source == "codex" ? "Codex" : "Claude")
    }
}

private struct StatusPanel: View {
    @ObservedObject var store: EventStore
    var body: some View {
        HStack(spacing: 12) {
            PixelInvader(color: VNColor.invader, px: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("vibe-notch").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 6) {
                    Circle().fill(ClaudeInstaller.isConnected ? VNColor.go : VNColor.faint).frame(width: 6, height: 6)
                    Text(ClaudeInstaller.isConnected ? "claude connected" : "not connected")
                        .font(.system(size: 11)).foregroundStyle(VNColor.muted)
                }
            }
            Spacer(minLength: 12)
        }
        .padding(EdgeInsets(top: 7, leading: 16, bottom: 9, trailing: 16))
        .frame(width: 300)
    }
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
        Text(source == "codex" ? "Codex" : "Claude")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Color(hex: 0x1A120E))
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(VNColor.agent(source), in: RoundedRectangle(cornerRadius: 6))
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
    enum Kind { case deny, primary, danger }
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
    private var bg: Color { switch kind { case .deny: VNColor.ink2; case .primary: .white; case .danger: Color(hex: 0xB0413F) } }
    private var fg: Color { switch kind { case .deny: VNColor.text; case .primary: .black; case .danger: .white } }
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
