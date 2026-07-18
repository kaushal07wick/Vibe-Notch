import AppKit
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
            .font(VNFont.sysMono(9.5, .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(tint.opacity(0.13), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
    }
}

/// Neutral side badge (model name, terminal name).
struct SideBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(VNFont.sysMono(9.5, .medium))
            .lineLimit(1).fixedSize()
            .foregroundStyle(VNColor.paper.opacity(0.7))
            .padding(.horizontal, 7).padding(.vertical, 2.5)
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

/// The real icon of the user's terminal app, straight from the system —
/// always correct, no bundled artwork. Falls back to a text badge.
struct TerminalIcon: View {
    let terminal: String

    private static var cache: [String: NSImage] = [:]
    private static let bundles: [String: [String]] = [
        "Ghostty":  ["com.mitchellh.ghostty"],
        "iTerm":    ["com.googlecode.iterm2"],
        "Terminal": ["com.apple.Terminal"],
        "Warp":     ["dev.warp.Warp-Stable", "dev.warp.Warp"],
        "kitty":    ["net.kovidgoyal.kitty"],
        "Alacritty":["org.alacritty"],
        "WezTerm":  ["com.github.wez.wezterm"],
        "VS Code":  ["com.microsoft.VSCode"],
    ]

    private static func icon(for terminal: String) -> NSImage? {
        if let hit = cache[terminal] { return hit }
        for id in bundles[terminal] ?? [] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                let img = NSWorkspace.shared.icon(forFile: url.path)
                cache[terminal] = img
                return img
            }
        }
        return nil
    }

    var body: some View {
        if let img = Self.icon(for: terminal) {
            Image(nsImage: img)
                .resizable().interpolation(.high)
                .frame(width: 16, height: 16)
                .help(terminal)
        } else {
            SideBadge(text: terminal)
        }
    }
}

/// The full pill cluster shown top-right of cards and rows.
struct PillCluster: View {
    let source: String
    var terminal: String?
    var tty: String?
    var showJump = true
    var age: Date?

    var body: some View {
        HStack(spacing: 5) {
            AgentPill(source: source)
            if let terminal { TerminalIcon(terminal: terminal) }
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
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
            ZStack {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if let hint {
                    // shortcut hint hugs the trailing edge (VI: "Allow Once   ^Y")
                    HStack {
                        Spacer()
                        Text(hint).font(VNFont.sysMono(10, .semibold)).opacity(0.5)
                    }
                    .padding(.trailing, 12)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .buttonStyle(PressFeedback())
        .background(background, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(Color.white.opacity(kind == .deny ? 0.09 : 0), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
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

/// Immediate visual press feedback — the click registers to the eye instantly.
struct PressFeedback: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Mascots & spinners

/// Per-agent brand glyph.
struct AgentIcon: View {
    let source: String
    var size: CGFloat = 16
    var body: some View {
        // each agent gets its own pixel brand mark (claude mascot, openai knot, …)
        AgentSpriteView(source: source, size: size)
    }
}

/// Radar sweep — a fat rotating wedge on a 7×7 grid. No walls: just a bright
/// dish and a solid beam slice with fading ghosts. Owl-eye amber.
struct PixelRingSpinner: View {
    var color: Color
    var px: CGFloat = 1.7
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 8 wedges — a chunky 5-cell slice per direction (dish excluded).
    private static let wedges: [[(Int, Int)]] = [
        [(3, 2), (3, 1), (3, 0), (2, 1), (4, 1)],          // N
        [(4, 2), (5, 1), (4, 1), (5, 2), (6, 0)],          // NE
        [(4, 3), (5, 3), (6, 3), (5, 2), (5, 4)],          // E
        [(4, 4), (5, 5), (5, 4), (4, 5), (6, 6)],          // SE
        [(3, 4), (3, 5), (3, 6), (2, 5), (4, 5)],          // S
        [(2, 4), (1, 5), (2, 5), (1, 4), (0, 6)],          // SW
        [(2, 3), (1, 3), (0, 3), (1, 2), (1, 4)],          // W
        [(2, 2), (1, 1), (2, 1), (1, 2), (0, 0)],          // NW
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.11)) { ctx in
            Canvas { c, _ in
                func put(_ x: Int, _ y: Int, _ alpha: Double) {
                    c.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px,
                                       width: px, height: px)),
                           with: .color(color.opacity(alpha)))
                }
                put(3, 3, active ? 1.0 : 0.4) // dish
                if active && !reduceMotion {
                    let i = Int(ctx.date.timeIntervalSinceReferenceDate / 0.11) % 8
                    for (x, y) in Self.wedges[i] { put(x, y, 0.95) }
                    for (x, y) in Self.wedges[(i + 7) % 8] { put(x, y, 0.4) }
                    for (x, y) in Self.wedges[(i + 6) % 8] { put(x, y, 0.16) }
                } else {
                    for (x, y) in [(3, 1), (5, 3), (3, 5), (1, 3)] { put(x, y, 0.2) }
                }
            }
            .frame(width: 7 * px, height: 7 * px)
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
