import SwiftUI

// Per-agent pixel-art brand sprites, drawn in code (no image assets).
// Grid chars → colors; `.` is transparent. Two frames = idle animation.

struct AgentSprite {
    let frameA: [String]
    var frameB: [String]?
    let colors: [Character: Color]
}

private let CLAUDE_ORANGE = Color(hex: 0xD97742)
private let INK = Color(hex: 0x141414)
private let PAPER = Color(hex: 0xF1EAD9)

let agentSprites: [String: AgentSprite] = [
    // Claude — the blocky orange mascot: body, eyes, little legs.
    "claude": AgentSprite(
        frameA: [
            "..oooooo..",
            ".oooooooo.",
            "oooooooooo",
            "oWkooooWko",
            "oooooooooo",
            "oooooooooo",
            ".oooooooo.",
            "..oo..oo..",
        ],
        frameB: [
            "..oooooo..",
            ".oooooooo.",
            "oooooooooo",
            "oWkooooWko",
            "oooooooooo",
            "oooooooooo",
            ".oooooooo.",
            ".oo....oo.",
        ],
        colors: ["o": CLAUDE_ORANGE, "W": PAPER, "k": INK]
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
