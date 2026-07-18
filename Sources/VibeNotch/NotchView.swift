import SwiftUI
import VibeNotchCore

// Content only — DynamicNotchKit draws the notch shape, background, and morph.
// We supply the expanded panel and the two compact flanks.

// MARK: - Expanded

/// The panel shown when the notch is expanded (an event, or on hover).
struct ExpandedContent: View {
    @ObservedObject var store: EventStore

    var body: some View {
        ZStack {
            currentCard
                .id(stateKey)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.94).combined(with: .opacity),
                    removal: .opacity))
        }
        .frame(width: 380)
        .foregroundStyle(VNColor.text)
        .animation(.spring(response: 0.36, dampingFraction: 0.78), value: stateKey)
        .overlay(alignment: .bottom) { GlowSeam(style: seam) }
    }

    /// Identity for the visible state — drives the cross-fade/scale transition.
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
            NotificationRow(inbound: note)
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

// MARK: - Compact flanks (either side of the physical notch)

struct CompactLeading: View {
    @ObservedObject var store: EventStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false
    var body: some View {
        PixelCaret(color: hue)
            .opacity(breathe ? 1 : 0.7)
            .padding(.leading, 10).padding(.trailing, 6)
            .onAppear {
                if !reduceMotion {
                    withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
                }
            }
    }
    private var hue: Color {
        if let a = store.pending.first { return VNColor.agent(a.inbound.source) }
        return VNColor.claude
    }
}

struct CompactTrailing: View {
    @ObservedObject var store: EventStore
    var body: some View {
        Circle().fill(dot)
            .frame(width: 7, height: 7)
            .padding(.trailing, 12).padding(.leading, 6)
    }
    private var dot: Color {
        if store.pending.first != nil { return VNColor.amber }
        if let f = store.flash { return f == .allow ? VNColor.go : VNColor.stop }
        if let n = store.lastNotification { return VNColor.agent(n.source) }
        return VNColor.faint
    }
}

// MARK: - Cards

private struct StatusPanel: View {
    @ObservedObject var store: EventStore
    var body: some View {
        HStack(spacing: 12) {
            AsciiCreature()
            VStack(alignment: .leading, spacing: 2) {
                Text("VIBE NOTCH").font(VNFont.mono(12)).tracking(0.5)
                HStack(spacing: 6) {
                    Circle().fill(ClaudeInstaller.isConnected ? VNColor.go : VNColor.faint).frame(width: 6, height: 6)
                    Text(ClaudeInstaller.isConnected ? "claude connected" : "not connected")
                        .font(VNFont.mono(10.5)).foregroundStyle(VNColor.muted)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }
}

/// A blinking ASCII cat in DepartureMono. First-pass mascot — frames cycle on a timeline.
struct AsciiCreature: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let frames = [
        " /\\_/\\\n( o.o )\n > ^ <",
        " /\\_/\\\n( -.- )\n > ^ <",
        " /\\_/\\\n( o.o )\n > ^ <",
        " /\\_/\\\n( o.O )\n > ^ <",
    ]
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let i = reduceMotion ? 0 : Int(ctx.date.timeIntervalSinceReferenceDate / 0.5) % frames.count
            Text(frames[i])
                .font(VNFont.mono(9))
                .lineSpacing(1)
                .foregroundStyle(VNColor.claude)
                .fixedSize()
        }
    }
}

private struct ApprovalCard: View {
    let approval: PendingApproval
    @ObservedObject var store: EventStore
    let queued: Int

    private var hue: Color { VNColor.agent(approval.inbound.source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle().fill(hue).frame(width: 8, height: 8)
                Text(approval.inbound.tool ?? approval.inbound.event)
                    .font(VNFont.mono(13))
                Spacer(minLength: 8)
                Text(approval.inbound.source.uppercased())
                    .font(VNFont.mono(9.5))
                    .tracking(1.2).foregroundStyle(VNColor.muted)
            }
            Text(approval.inbound.detail ?? "—")
                .font(VNFont.mono(12))
                .lineLimit(2).truncationMode(.middle)
                .foregroundStyle(Color(hex: 0xDFE0DD))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VNColor.ink2, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(VNColor.hair))
            HStack(spacing: 8) {
                if let cwd = approval.inbound.cwd {
                    Text(abbreviate(cwd))
                        .font(VNFont.mono(10.5))
                        .foregroundStyle(VNColor.muted)
                        .lineLimit(1).truncationMode(.head)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(VNColor.ink2, in: RoundedRectangle(cornerRadius: 6))
                }
                Spacer(minLength: 4)
                if queued > 0 {
                    Text("\(queued) more").font(.system(size: 10)).foregroundStyle(VNColor.faint)
                }
                Button("Deny") { store.resolve(approval, .deny) }
                    .buttonStyle(NotchButton(kind: .deny))
                Button("Approve") { store.resolve(approval, .allow) }
                    .buttonStyle(NotchButton(kind: .approve(hue)))
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
    }

    private func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

private struct NotificationRow: View {
    let inbound: VNInbound
    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(VNColor.agent(inbound.source)).frame(width: 8, height: 8)
            Text(inbound.detail ?? label)
                .font(VNFont.mono(12)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            if inbound.source == "codex" {
                Text("Jump ↵").font(.system(size: 11)).foregroundStyle(VNColor.text)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(VNColor.hair))
            } else {
                Text("now").font(.system(size: 11)).foregroundStyle(VNColor.faint)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }
    private var label: String { inbound.source == "codex" ? "Codex is waiting for input" : inbound.event }
}

private struct FlashPill: View {
    let decision: VNDecision
    @State private var shown = false
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: decision == .allow ? "checkmark" : "xmark")
                .font(.system(size: 11, weight: .bold))
                .scaleEffect(shown ? 1 : 0.3)
                .opacity(shown ? 1 : 0)
            Text(decision == .allow ? "Approved" : "Denied").font(.system(size: 12.5, weight: .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(decision == .allow ? VNColor.go : VNColor.stop)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .onAppear { withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { shown = true } }
    }
}

// MARK: - Shared pieces

struct SeamStyle { var color: Color; var pulses: Bool; var dim: Bool = false }

private struct GlowSeam: View {
    let style: SeamStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        Capsule().fill(style.color)
            .frame(height: 2).shadow(color: style.color, radius: 6)
            .padding(.horizontal, 40).padding(.bottom, 3)
            .opacity(style.dim ? 0.45 : (style.pulses ? (on ? 1 : 0.4) : 0.9))
            .onAppear {
                if style.pulses && !reduceMotion {
                    withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { on = true }
                }
            }
    }
}

/// The pixel caret — the notch is a caret. 7×4 downward chevron.
struct PixelCaret: View {
    var color: Color
    var px: CGFloat = 3
    private let cells: [(Int, Int)] = [(0,0),(6,0),(1,1),(5,1),(2,2),(4,2),(3,3)]
    var body: some View {
        Canvas { ctx, _ in
            for (c, r) in cells {
                ctx.fill(Path(CGRect(x: CGFloat(c) * px, y: CGFloat(r) * px, width: px, height: px)),
                         with: .color(color))
            }
        }
        .frame(width: 7 * px, height: 4 * px)
        .shadow(color: color.opacity(0.5), radius: 2)
    }
}

private struct NotchButton: ButtonStyle {
    enum Kind { case deny; case approve(Color) }
    let kind: Kind
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(VNFont.mono(12))
            .padding(.horizontal, 15).padding(.vertical, 6)
        switch kind {
        case .deny:
            return AnyView(label.foregroundStyle(VNColor.text)
                .background(VNColor.ink2, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(VNColor.hair))
                .opacity(configuration.isPressed ? 0.7 : 1))
        case .approve(let hue):
            return AnyView(label.foregroundStyle(Color(hex: 0x16110E))
                .background(hue, in: RoundedRectangle(cornerRadius: 9))
                .brightness(configuration.isPressed ? -0.06 : 0))
        }
    }
}
