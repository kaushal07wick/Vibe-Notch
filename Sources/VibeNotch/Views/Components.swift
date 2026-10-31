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
    var meta: [String: String] = [:]
    var body: some View {
        Button { TerminalJumper.jump(terminal: terminal, tty: tty, meta: meta) } label: {
            HStack(spacing: 3) {
                Text("^G").font(VNFont.mono(9.5))
                Image(systemName: "arrow.up.forward").font(VNFont.ui(8, .bold))
            }
            .foregroundStyle(Color(hex: 0x6FD3E0))
            .padding(.horizontal, 8).frame(minHeight: 28)
            .background(Color(hex: 0x123238), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to the agent's terminal tab")
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
    var meta: [String: String] = [:]
    var showJump = true
    var age: Date?

    var body: some View {
        HStack(spacing: 5) {
            if let terminal { TerminalIcon(terminal: terminal) }
            if showJump { JumpPill(terminal: terminal, tty: tty, meta: meta) }
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
    /// Spoken name — the glyph alone tells VoiceOver nothing.
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(VNFont.ui(12.5, .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
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
                Text(title).font(VNFont.ui(12, .semibold)).lineLimit(1)
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
            .accessibilityLabel(agentName(source))
    }
}

/// Eight discrete pixels, eight frames per second. No blur or continuous spin.
struct PixelRingSpinner: View {
    var color: Color
    var px: CGFloat = 1.7
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.125, paused: !active || reduceMotion)) { timeline in
            let cell = max(1, (px * displayScale).rounded() / displayScale)
            let phase = active && !reduceMotion ? Int(timeline.date.timeIntervalSinceReferenceDate * 8) % 8 : 0
            Canvas { context, _ in
                let points = [(2, 0), (4, 0), (6, 2), (6, 4), (4, 6), (2, 6), (0, 4), (0, 2)]
                for (index, point) in points.enumerated() {
                    let age = (index - phase + 8) % 8
                    let opacity = active ? max(0.18, 1 - Double(age) * 0.13) : 0.25
                    context.fill(Path(CGRect(x: CGFloat(point.0) * cell, y: CGFloat(point.1) * cell,
                                             width: cell, height: cell)), with: .color(color.opacity(opacity)))
                }
            }
            .frame(width: cell * 7, height: cell * 7)
        }
        .accessibilityHidden(true)
    }
}

/// The animated two-frame pixel space invader mascot.
struct PixelInvader: View {
    var color: Color
    var px: CGFloat = 2.5
    var animated = true
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
        // Whole-device-pixel cells; a fractional px blurs pixel art.
        let px = max(1, (self.px * 2).rounded() / 2)
        TimelineView(.animation(minimumInterval: 0.4, paused: !animated || reduceMotion)) { ctx in
            let useA = !animated || reduceMotion || Int(ctx.date.timeIntervalSinceReferenceDate / 0.4) % 2 == 0
            let f = cells(useA ? Self.frameA : Self.frameB)
            Canvas { c, _ in
                for (x, y) in f {
                    c.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px)),
                           with: .color(color))
                }
            }
            .frame(width: 11 * px, height: 8 * px)
        }
        .accessibilityHidden(true) // decoration; the state it sits beside is labelled
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

/// The notch mascot: a little ghost. Eyes glance side to side and the hem ripples
/// while agents work; asleep (eyes shut) when idle. X body, W eye white, P pupil.
struct PixelGhost: View {
    enum Mood { case idle, working, waiting }
    var mood: Mood
    var px: CGFloat = 1.5
    /// Context nearly full: a drop runs down beside its head.
    var sweat = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // b body · l highlight · d shade · o outline · p cheek · E/e eye (2x2: top/bottom)
    private static let top = [
        "...oooooo...", "..oblbbbbbo.", ".oblbbbbbbbo", ".obbbbbbbbbo",
        ".obbEEbbEEbo", ".obbeebbeebo", ".obpbbbbbpbo",
        ".obbbbbbbbdo", ".obbbbbbbddo", ".obbbbbbbddo",
    ]
    private static let hemA = [".obbobbobbo.", "..oo.oo.oo.."]
    private static let hemB = [".obobbobbob.", "..o.oo.oo.o."]

    private static let blue: [Character: Color] = [
        "b": Color(red: 0.48, green: 0.65, blue: 1), "l": Color(red: 0.73, green: 0.82, blue: 1),
        "d": Color(red: 0.31, green: 0.47, blue: 0.85), "o": Color(red: 0.16, green: 0.25, blue: 0.48),
        "p": Color(red: 1, green: 0.62, blue: 0.75),
    ]
    private static let amber: [Character: Color] = [
        "b": Color(red: 1, green: 0.75, blue: 0.24), "l": Color(red: 1, green: 0.88, blue: 0.54),
        "d": Color(red: 0.85, green: 0.6, blue: 0.06), "o": Color(red: 0.42, green: 0.29, blue: 0.02),
        "p": Color(red: 1, green: 0.62, blue: 0.75),
    ]

    var body: some View {
        let px = max(1, (self.px * 2).rounded() / 2)
        let moving = (mood != .idle || sweat) && !reduceMotion
        TimelineView(.animation(minimumInterval: 0.2, paused: !moving)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let beat = Int(t / 0.4)
            let blink = moving && mood == .working && t.truncatingRemainder(dividingBy: 3.2) < 0.15
            let look = beat / 2 % 2
            let rows = (Self.top + (moving && beat % 2 == 1 ? Self.hemB : Self.hemA)).map { row -> [Character] in
                var idx = 0
                return row.enumerated().map { i, ch -> Character in
                    guard ch == "E" || ch == "e" else { idx = 0; return ch }
                    let prev = i > 0 && Array(row)[i - 1] == ch
                    idx = prev ? 1 : 0
                    if mood == .idle || blink { return ch == "E" ? "b" : "o" }
                    if mood == .waiting { return ch == "E" && idx == 0 ? "w" : "k" }
                    return ch == "E" ? "w" : (idx == look ? "k" : "w")
                }
            }
            let pal = mood == .waiting ? Self.amber : Self.blue
            Canvas { c, _ in
                for (y, row) in rows.enumerated() {
                    for (x, ch) in row.enumerated() where ch != "." {
                        let fill: Color = ch == "w" ? .white : ch == "k" ? Color(red: 0.06, green: 0.09, blue: 0.19) : pal[ch] ?? .clear
                        c.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px)),
                               with: .color(fill))
                    }
                }
                if sweat {   // a drop just off the right of the head, sliding down then resetting
                    let y = CGFloat(2 + (reduceMotion ? 1 : beat % 4))
                    c.fill(Path(CGRect(x: 12 * px, y: y * px, width: px, height: 2 * px)),
                           with: .color(Color(red: 0.62, green: 0.86, blue: 1)))
                    c.fill(Path(CGRect(x: 12 * px, y: y * px, width: px, height: px)), with: .color(.white.opacity(0.85)))
                }
            }
            .frame(width: (sweat ? 13 : 12) * px, height: 12 * px)
        }
        .accessibilityHidden(true)
    }
}
