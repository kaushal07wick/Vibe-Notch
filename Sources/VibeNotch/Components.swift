import SwiftUI
import VibeNotchCore

// Shared UI atoms: pills, buttons, mascots, small helpers.

// MARK: - Pills

/// Tinted-mono agent capsule — brand-colored text on a faint brand fill.
struct AgentPill: View {
    let source: String
    var body: some View {
        let tint = VNColor.agent(source)
        Text(agentName(source))
            .font(VNFont.sysMono(10.5, .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.13), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
    }
}

/// Neutral side badge (model name, terminal name).
struct SideBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(VNFont.sysMono(10.5, .medium))
            .foregroundStyle(VNColor.paper.opacity(0.7))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.white.opacity(0.06), in: Capsule())
    }
}

/// The ^G jump-to-terminal pill — exact tab when the session tty is known.
struct JumpPill: View {
    let terminal: String?
    var tty: String?
    var body: some View {
        Button { TerminalJumper.jump(terminal: terminal, tty: tty) } label: {
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

/// The full pill cluster shown top-right of cards and rows.
struct PillCluster: View {
    let source: String
    var model: String?
    var terminal: String?
    var tty: String?
    var showJump = true
    var age: Date?

    var body: some View {
        HStack(spacing: 5) {
            AgentPill(source: source)
            if let model { SideBadge(text: model) }
            if let terminal { SideBadge(text: terminal) }
            if showJump { JumpPill(terminal: terminal, tty: tty) }
            if let age {
                Text(ageString(age)).font(VNFont.sysMono(10.5, .medium))
                    .foregroundStyle(VNColor.paper.opacity(0.45))
                    .frame(minWidth: 28, alignment: .trailing)
            }
        }
    }
}

// MARK: - Buttons

/// Round header icon button (mute, settings) — VI recipe.
struct HeaderIconButton: View {
    let symbol: String
    let tint: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Full-width action button used on the approval card (VI metrics).
/// `hint` renders a keyboard shortcut ("^A") inside the button, VI-style.
struct WideButton: View {
    enum Kind { case deny, primary, always, danger }
    let title: String
    let kind: Kind
    var hint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 11.8, weight: .semibold))
                if let hint {
                    Text(hint).font(VNFont.sysMono(9.5, .semibold)).opacity(0.55)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.white.opacity(kind == .deny ? 0.09 : 0), lineWidth: 1))
        .foregroundStyle(foreground)
    }

    private var background: Color {
        switch kind {
        case .deny: VNColor.ink2
        case .primary: .white
        case .always: VNColor.invader
        case .danger: Color(hex: 0xB0413F)
        }
    }
    private var foreground: Color { if case .primary = kind { .black } else { .white } }
}

// MARK: - Mascots & spinners

/// Per-agent brand glyph.
struct AgentIcon: View {
    let source: String
    var size: CGFloat = 16
    var body: some View {
        Image(systemName: source == "codex" ? "asterisk" : "sparkle")
            .font(.system(size: size * 0.85, weight: .semibold))
            .foregroundStyle(VNColor.agent(source))
    }
}

/// A rotating braille spinner — the "working" ASCII animation.
struct AsciiSpinner: View {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.09)) { ctx in
            let i = reduceMotion ? 0 : Int(ctx.date.timeIntervalSinceReferenceDate / 0.09) % frames.count
            Text(frames[i])
                .font(VNFont.mono(12))
                .foregroundStyle(color)
                .frame(width: 12, alignment: .center)
        }
    }
}

/// The animated two-frame pixel space invader mascot.
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

// MARK: - Helpers

/// Relative age: <1m / Nm / Nh / Nd
func ageString(_ date: Date) -> String {
    let s = max(0, Int(Date().timeIntervalSince(date)))
    if s < 60 { return "<1m" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    return "\(s / 86400)d"
}

/// "folder · task" title used across cards and rows.
func sessionTitle(folder: String?, task: String?) -> String {
    let f = folder ?? "session"
    if let task, !task.isEmpty { return "\(f) · \(task)" }
    return f
}
