import SwiftUI
import VibeNotchCore

// Per-agent pixel-art brand sprites, drawn in code (no image assets).
// Grid chars → colors; `.` is transparent. Two frames = idle animation.

struct AgentSprite {
    let frameA: [String]
    var frameB: [String]?
    let colors: [Character: Color]
}

private let CLAUDE_ORANGE = Color(hex: 0xDD775B) // exact fill from Anthropic's mascot clips
private let INK = Color(hex: 0x141414)
private let PAPER = Color(hex: 0xF1EAD9)

let agentSprites: [String: AgentSprite] = [
    // Claude — transcribed from the mascot demo's actual SVG rects
    // (ayotomcs.me/claude-mascot): body x11–96 y0–60, black 11×11 eyes at
    // (21,11)/(75,11), side hands 22×23 at y21, four 11×26 legs at
    // x 11/32/64/85. 1 grid cell ≈ 11px. Frame B = the walk's leg shift.
    "claude": AgentSprite(
        frameA: [
            ".oooooooo.",
            ".okooooko.",
            "oooooooooo",
            "oooooooooo",
            ".oooooooo.",
            ".oooooooo.",
            ".o.o..o.o.",
            ".o.o..o.o.",
        ],
        frameB: [
            ".oooooooo.",
            ".okooooko.",
            "oooooooooo",
            "oooooooooo",
            ".oooooooo.",
            ".oooooooo.",
            "..o.o..o.o",
            "..o.o..o.o",
        ],
        colors: ["o": CLAUDE_ORANGE, "k": .black]
    ),
    // OpenAI (Codex) — hexagonal knot ring.
    "codex": AgentSprite(
        frameA: [
            "..oooooo..",
            ".oo....oo.",
            "oo..oo..oo",
            "o..o..o..o",
            "o..o..o..o",
            "oo..oo..oo",
            ".oo....oo.",
            "..oooooo..",
        ],
        colors: ["o": Color(hex: 0x74AA9C)]
    ),
    // Gemini — four-point star.
    "gemini": AgentSprite(
        frameA: [
            "....oo....",
            "...oooo...",
            "..oooooo..",
            ".oooooooo.",
            ".oooooooo.",
            "..oooooo..",
            "...oooo...",
            "....oo....",
        ],
        colors: ["o": Color(hex: 0x4796E3)]
    ),
    // Cursor — pointer arrow.
    "cursor": AgentSprite(
        frameA: [
            "o.........",
            "oo........",
            "ooo.......",
            "oooo......",
            "ooooo.....",
            "oooooo....",
            "oo..oo....",
            "o....oo...",
        ],
        colors: ["o": Color(hex: 0xC8CDD4)]
    ),
    // Qwen — interlocked diamond ring with tail.
    "qwen": AgentSprite(
        frameA: [
            "...oooo...",
            "..oo..oo..",
            ".oo....oo.",
            ".oo....oo.",
            "..oo..oo..",
            "...oooo...",
            ".....oo...",
            "......oo..",
        ],
        colors: ["o": Color(hex: 0xC084FC)]
    ),
    // Kimi (Moonshot) — crescent moon.
    "kimi": AgentSprite(
        frameA: [
            "...oooo...",
            ".ooo......",
            ".oo.......",
            "oo........",
            "oo........",
            ".oo.......",
            ".ooo......",
            "...oooo...",
        ],
        colors: ["o": Color(hex: 0xFDE047)]
    ),
    // OpenCode — terminal prompt >_
    "opencode": AgentSprite(
        frameA: [
            "oo........",
            ".oo.......",
            "..oo......",
            "...oo.....",
            "..oo......",
            ".oo.......",
            "oo...ooooo",
            "..........",
        ],
        colors: ["o": Color(hex: 0xFFB547)]
    ),
    // Factory Droid — robot head.
    "droid": AgentSprite(
        frameA: [
            "...o..o...",
            "..oooooo..",
            ".oooooooo.",
            ".oWkooWko.",
            ".oooooooo.",
            ".oo.oo.oo.",
            "..oooooo..",
            "..o....o..",
        ],
        colors: ["o": Color(hex: 0x6E9FFF), "W": PAPER, "k": INK]
    ),
    // Qoder — pixel Q.
    "qoder": AgentSprite(
        frameA: [
            "..oooooo..",
            ".oo....oo.",
            ".oo....oo.",
            ".oo....oo.",
            ".oo..o.oo.",
            ".oo...ooo.",
            "..oooooo..",
            ".......oo.",
        ],
        colors: ["o": Color(hex: 0xFF6B9F)]
    ),
    // CodeBuddy — buddy face.
    "codebuddy": AgentSprite(
        frameA: [
            "..oooooo..",
            ".oooooooo.",
            "oo.oo.oo.o",
            "oooooooooo",
            "oo......oo",
            "ooo....ooo",
            ".oooooooo.",
            "..oooooo..",
        ],
        colors: ["o": Color(hex: 0xFCA5A5)]
    ),
]

/// Small pixel-art status glyphs drawn next to the mascot (VI style).
struct PixelGlyph: View {
    static let question = [
        ".ooo.",
        "o...o",
        "....o",
        "...o.",
        "..o..",
        ".....",
        "..o..",
    ]
    let grid: [String]
    let color: Color
    var px: CGFloat = 2

    var body: some View {
        Canvas { c, _ in
            for (y, row) in grid.enumerated() {
                for (x, ch) in row.enumerated() where ch == "o" {
                    c.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px)),
                           with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(grid[0].count) * px, height: CGFloat(grid.count) * px)
    }
}

/// Draws an agent's pixel sprite scaled to `size` (width), animating between
/// frames when the sprite has two. Falls back to the generic invader.
struct AgentSpriteView: View {
    let source: String
    var size: CGFloat = 20
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let sprite = agentSprites[source] {
            let cols = CGFloat(sprite.frameA[0].count)
            let rows = CGFloat(sprite.frameA.count)
            let px = size / cols
            TimelineView(.periodic(from: .now, by: 0.45)) { ctx in
                let useA = reduceMotion || sprite.frameB == nil
                    || Int(ctx.date.timeIntervalSinceReferenceDate / 0.45) % 2 == 0
                let grid = useA ? sprite.frameA : sprite.frameB!
                Canvas { c, _ in
                    for (y, row) in grid.enumerated() {
                        for (x, ch) in row.enumerated() {
                            guard let color = sprite.colors[ch] else { continue }
                            c.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px,
                                               width: px, height: px)),
                                   with: .color(color))
                        }
                    }
                }
                .frame(width: cols * px, height: rows * px)
            }
        } else {
            PixelInvader(color: VNColor.agent(source), px: size / 11)
        }
    }
}

// MARK: - Mascot evolution

/// The invader grows with lifetime activity (StatsLog.mascotLevel 1…5):
/// color deepens, antennae at 3+, a gold crown at 4+.
struct EvolvedInvader: View {
    var px: CGFloat = 2
    @State private var level = 1

    private static let levelColors: [Color] = [
        Color(hex: 0x4F7DF0),  // 1 — blue
        Color(hex: 0x42B883),  // 2 — green
        Color(hex: 0x3AA8A0),  // 3 — teal
        Color(hex: 0x9B6DFF),  // 4 — violet
        Color(hex: 0xE8B33C),  // 5 — gold
    ]

    var body: some View {
        VStack(spacing: px * 0.5) {
            if level >= 4 {
                PixelGlyph(grid: ["o.o.o"], color: Color(hex: 0xE8B33C), px: px) // crown
            }
            PixelInvader(color: Self.levelColors[min(level, 5) - 1], px: px)
        }
        .onAppear { level = StatsLog.mascotLevel(totals: StatsLog.totals()) }
        .help("Invader level \(level)/5 — grows with your sessions")
    }
}

/// Session-state glyph shown beside the mascot in rows (VI's language).
struct StatusGlyph: View {
    let event: String
    var body: some View {
        switch event {
        case "PermissionRequest":
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8)).foregroundStyle(VNColor.amber)
        case "Notification":
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 8)).foregroundStyle(VNColor.amber)
        case "PreToolUse", "PostToolUse", "UserPromptSubmit":
            Image(systemName: "circle.dashed")
                .font(.system(size: 8)).foregroundStyle(VNColor.running)
        case "Stop":
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 8)).foregroundStyle(VNColor.go)
        case "PostToolUseFailure", "StopFailure":
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 8)).foregroundStyle(VNColor.stop)
        default:
            EmptyView()
        }
    }
}
