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


// MARK: - OpenAI mark (baked from the official SVG, unit coordinates)

struct OpenAILogoShape: Shape {
    func path(in rect: CGRect) -> SwiftUI.Path {
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var p = SwiftUI.Path()
        p.move(to: P(0.3835, 0.3607))
        p.addLine(to: P(0.3835, 0.2666))
        p.addCurve(to: P(0.3935, 0.2487), control1: P(0.3835, 0.2587), control2: P(0.3865, 0.2527))
        p.addLine(to: P(0.5827, 0.1397))
        p.addCurve(to: P(0.6710, 0.1180), control1: P(0.6085, 0.1249), control2: P(0.6392, 0.1180))
        p.addCurve(to: P(0.8652, 0.3082), control1: P(0.7899, 0.1180), control2: P(0.8652, 0.2101))
        p.addCurve(to: P(0.8642, 0.3310), control1: P(0.8652, 0.3152), control2: P(0.8652, 0.3231))
        p.addLine(to: P(0.6680, 0.2160))
        p.addCurve(to: P(0.6564, 0.2114), control1: P(0.6644, 0.2138), control2: P(0.6605, 0.2122))
        p.addCurve(to: P(0.6439, 0.2114), control1: P(0.6522, 0.2106), control2: P(0.6480, 0.2106))
        p.addCurve(to: P(0.6323, 0.2160), control1: P(0.6398, 0.2122), control2: P(0.6358, 0.2138))
        p.addLine(to: P(0.3835, 0.3607))
        p.closeSubpath()
        p.move(to: P(0.8256, 0.7274))
        p.addLine(to: P(0.8256, 0.5025))
        p.addCurve(to: P(0.8077, 0.4718), control1: P(0.8256, 0.4886), control2: P(0.8196, 0.4788))
        p.addLine(to: P(0.5590, 0.3271))
        p.addLine(to: P(0.6402, 0.2805))
        p.addCurve(to: P(0.6466, 0.2779), control1: P(0.6422, 0.2792), control2: P(0.6444, 0.2783))
        p.addCurve(to: P(0.6536, 0.2779), control1: P(0.6489, 0.2774), control2: P(0.6513, 0.2774))
        p.addCurve(to: P(0.6600, 0.2805), control1: P(0.6559, 0.2783), control2: P(0.6581, 0.2792))
        p.addLine(to: P(0.8493, 0.3895))
        p.addCurve(to: P(0.9405, 0.5540), control1: P(0.9039, 0.4212), control2: P(0.9405, 0.4886))
        p.addCurve(to: P(0.8255, 0.7275), control1: P(0.9405, 0.6294), control2: P(0.8960, 0.6987))
        p.closeSubpath()
        p.move(to: P(0.3251, 0.5293))
        p.addLine(to: P(0.2438, 0.4817))
        p.addCurve(to: P(0.2339, 0.4639), control1: P(0.2369, 0.4777), control2: P(0.2339, 0.4718))
        p.addLine(to: P(0.2339, 0.2458))
        p.addCurve(to: P(0.4252, 0.0595), control1: P(0.2339, 0.1398), control2: P(0.3151, 0.0595))
        p.addCurve(to: P(0.5382, 0.0981), control1: P(0.4668, 0.0595), control2: P(0.5055, 0.0733))
        p.addLine(to: P(0.3429, 0.2111))
        p.addCurve(to: P(0.3251, 0.2418), control1: P(0.3310, 0.2180), control2: P(0.3251, 0.2280))
        p.addLine(to: P(0.3251, 0.5292))
        p.closeSubpath()
        p.move(to: P(0.5000, 0.6303))
        p.addLine(to: P(0.3835, 0.5649))
        p.addLine(to: P(0.3835, 0.4262))
        p.addLine(to: P(0.5000, 0.3607))
        p.addLine(to: P(0.6165, 0.4262))
        p.addLine(to: P(0.6165, 0.5649))
        p.addLine(to: P(0.5000, 0.6303))
        p.closeSubpath()
        p.move(to: P(0.5748, 0.9316))
        p.addCurve(to: P(0.4618, 0.8930), control1: P(0.5332, 0.9316), control2: P(0.4945, 0.9177))
        p.addLine(to: P(0.6571, 0.7800))
        p.addCurve(to: P(0.6749, 0.7493), control1: P(0.6690, 0.7730), control2: P(0.6749, 0.7631))
        p.addLine(to: P(0.6749, 0.4618))
        p.addLine(to: P(0.7572, 0.5094))
        p.addCurve(to: P(0.7671, 0.5273), control1: P(0.7641, 0.5134), control2: P(0.7671, 0.5193))
        p.addLine(to: P(0.7671, 0.7453))
        p.addCurve(to: P(0.5748, 0.9316), control1: P(0.7671, 0.8513), control2: P(0.6848, 0.9316))
        p.closeSubpath()
        p.move(to: P(0.3400, 0.7106))
        p.addLine(to: P(0.1506, 0.6016))
        p.addCurve(to: P(0.0595, 0.4371), control1: P(0.0961, 0.5699), control2: P(0.0595, 0.5025))
        p.addCurve(to: P(0.0736, 0.3651), control1: P(0.0594, 0.4124), control2: P(0.0642, 0.3880))
        p.addCurve(to: P(0.1143, 0.3042), control1: P(0.0830, 0.3423), control2: P(0.0969, 0.3216))
        p.addCurve(to: P(0.1754, 0.2636), control1: P(0.1318, 0.2868), control2: P(0.1526, 0.2730))
        p.addLine(to: P(0.1754, 0.4896))
        p.addCurve(to: P(0.1933, 0.5203), control1: P(0.1754, 0.5035), control2: P(0.1814, 0.5134))
        p.addLine(to: P(0.4410, 0.6640))
        p.addLine(to: P(0.3598, 0.7106))
        p.addCurve(to: P(0.3534, 0.7133), control1: P(0.3578, 0.7119), control2: P(0.3557, 0.7128))
        p.addCurve(to: P(0.3464, 0.7133), control1: P(0.3511, 0.7137), control2: P(0.3487, 0.7137))
        p.addCurve(to: P(0.3400, 0.7106), control1: P(0.3441, 0.7128), control2: P(0.3419, 0.7119))
        p.closeSubpath()
        p.move(to: P(0.3290, 0.8731))
        p.addCurve(to: P(0.1348, 0.6848), control1: P(0.2170, 0.8731), control2: P(0.1348, 0.7889))
        p.addCurve(to: P(0.1367, 0.6611), control1: P(0.1348, 0.6769), control2: P(0.1358, 0.6690))
        p.addLine(to: P(0.3320, 0.7740))
        p.addCurve(to: P(0.3677, 0.7740), control1: P(0.3439, 0.7810), control2: P(0.3558, 0.7810))
        p.addLine(to: P(0.6164, 0.6303))
        p.addLine(to: P(0.6164, 0.7245))
        p.addCurve(to: P(0.6065, 0.7423), control1: P(0.6164, 0.7324), control2: P(0.6135, 0.7384))
        p.addLine(to: P(0.4172, 0.8513))
        p.addCurve(to: P(0.3290, 0.8731), control1: P(0.3915, 0.8662), control2: P(0.3607, 0.8731))
        p.closeSubpath()
        p.move(to: P(0.5748, 0.9910))
        p.addCurve(to: P(0.6840, 0.9657), control1: P(0.6127, 0.9910), control2: P(0.6501, 0.9824))
        p.addCurve(to: P(0.7709, 0.8948), control1: P(0.7180, 0.9490), control2: P(0.7477, 0.9247))
        p.addCurve(to: P(0.8176, 0.7929), control1: P(0.7941, 0.8648), control2: P(0.8100, 0.8300))
        p.addCurve(to: P(1.0000, 0.5540), control1: P(0.9286, 0.7641), control2: P(1.0000, 0.6600))
        p.addCurve(to: P(0.9167, 0.3687), control1: P(1.0000, 0.4846), control2: P(0.9703, 0.4172))
        p.addCurve(to: P(0.9247, 0.3062), control1: P(0.9217, 0.3478), control2: P(0.9247, 0.3270))
        p.addCurve(to: P(0.6769, 0.0585), control1: P(0.9247, 0.1645), control2: P(0.8097, 0.0585))
        p.addCurve(to: P(0.5986, 0.0714), control1: P(0.6502, 0.0585), control2: P(0.6244, 0.0624))
        p.addCurve(to: P(0.5189, 0.0187), control1: P(0.5757, 0.0488), control2: P(0.5486, 0.0309))
        p.addCurve(to: P(0.4252, 0.0000), control1: P(0.4892, 0.0065), control2: P(0.4574, 0.0001))
        p.addCurve(to: P(0.3160, 0.0254), control1: P(0.3873, -0.0000), control2: P(0.3500, 0.0087))
        p.addCurve(to: P(0.2291, 0.0963), control1: P(0.2820, 0.0421), control2: P(0.2523, 0.0663))
        p.addCurve(to: P(0.1824, 0.1982), control1: P(0.2060, 0.1262), control2: P(0.1900, 0.1611))
        p.addCurve(to: P(0.0000, 0.4371), control1: P(0.0714, 0.2270), control2: P(0.0000, 0.3310))
        p.addCurve(to: P(0.0833, 0.6224), control1: P(0.0000, 0.5065), control2: P(0.0297, 0.5739))
        p.addCurve(to: P(0.0753, 0.6849), control1: P(0.0783, 0.6432), control2: P(0.0753, 0.6641))
        p.addCurve(to: P(0.3231, 0.9326), control1: P(0.0753, 0.8266), control2: P(0.1903, 0.9326))
        p.addCurve(to: P(0.4014, 0.9198), control1: P(0.3498, 0.9326), control2: P(0.3756, 0.9287))
        p.addCurve(to: P(0.4811, 0.9724), control1: P(0.4243, 0.9423), control2: P(0.4514, 0.9602))
        p.addCurve(to: P(0.5748, 0.9911), control1: P(0.5109, 0.9847), control2: P(0.5427, 0.9910))
        p.closeSubpath()
        return p
    }
}

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
        if source == "codex" {
            OpenAILogoShape()
                .fill(Color(hex: 0xE8E8E3))
                .frame(width: size, height: size)
        } else if let sprite = agentSprites[source] {
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
