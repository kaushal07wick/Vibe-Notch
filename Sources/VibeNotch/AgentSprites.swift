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



// MARK: - Real brand marks (baked from official SVGs, unit coordinates)

private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

enum BrandPaths {
    static let gemini: SwiftUI.Path = {
        var p = SwiftUI.Path()
        p.move(to: P(0.8590, 0.4515))
        p.addCurve(to: P(0.6736, 0.3264), control1: P(0.7898, 0.4220), control2: P(0.7268, 0.3795))
        p.addCurve(to: P(0.5790, 0.2023), control1: P(0.6367, 0.2894), control2: P(0.6048, 0.2477))
        p.addCurve(to: P(0.5203, 0.0576), control1: P(0.5531, 0.1569), control2: P(0.5334, 0.1082))
        p.addCurve(to: P(0.5162, 0.0494), control1: P(0.5196, 0.0546), control2: P(0.5182, 0.0518))
        p.addCurve(to: P(0.5090, 0.0438), control1: P(0.5142, 0.0470), control2: P(0.5118, 0.0451))
        p.addCurve(to: P(0.5000, 0.0418), control1: P(0.5062, 0.0425), control2: P(0.5031, 0.0418))
        p.addCurve(to: P(0.4911, 0.0438), control1: P(0.4969, 0.0418), control2: P(0.4939, 0.0425))
        p.addCurve(to: P(0.4839, 0.0494), control1: P(0.4883, 0.0451), control2: P(0.4858, 0.0470))
        p.addCurve(to: P(0.4797, 0.0576), control1: P(0.4819, 0.0518), control2: P(0.4805, 0.0546))
        p.addCurve(to: P(0.4210, 0.2022), control1: P(0.4667, 0.1082), control2: P(0.4469, 0.1568))
        p.addCurve(to: P(0.3264, 0.3264), control1: P(0.3951, 0.2477), control2: P(0.3633, 0.2894))
        p.addCurve(to: P(0.1410, 0.4515), control1: P(0.2732, 0.3795), control2: P(0.2102, 0.4220))
        p.addCurve(to: P(0.0576, 0.4797), control1: P(0.1139, 0.4631), control2: P(0.0861, 0.4725))
        p.addCurve(to: P(0.0494, 0.4838), control1: P(0.0546, 0.4804), control2: P(0.0518, 0.4819))
        p.addCurve(to: P(0.0437, 0.4910), control1: P(0.0469, 0.4858), control2: P(0.0450, 0.4882))
        p.addCurve(to: P(0.0417, 0.5000), control1: P(0.0423, 0.4939), control2: P(0.0417, 0.4969))
        p.addCurve(to: P(0.0437, 0.5090), control1: P(0.0417, 0.5031), control2: P(0.0423, 0.5062))
        p.addCurve(to: P(0.0494, 0.5162), control1: P(0.0450, 0.5118), control2: P(0.0469, 0.5143))
        p.addCurve(to: P(0.0576, 0.5203), control1: P(0.0518, 0.5182), control2: P(0.0546, 0.5196))
        p.addCurve(to: P(0.1410, 0.5485), control1: P(0.0861, 0.5275), control2: P(0.1138, 0.5369))
        p.addCurve(to: P(0.3264, 0.6736), control1: P(0.2102, 0.5780), control2: P(0.2732, 0.6205))
        p.addCurve(to: P(0.4211, 0.7978), control1: P(0.3633, 0.7106), control2: P(0.3952, 0.7523))
        p.addCurve(to: P(0.4797, 0.9425), control1: P(0.4470, 0.8432), control2: P(0.4667, 0.8918))
        p.addCurve(to: P(0.4838, 0.9507), control1: P(0.4804, 0.9455), control2: P(0.4819, 0.9483))
        p.addCurve(to: P(0.4910, 0.9564), control1: P(0.4858, 0.9531), control2: P(0.4882, 0.9550))
        p.addCurve(to: P(0.5000, 0.9584), control1: P(0.4939, 0.9577), control2: P(0.4969, 0.9584))
        p.addCurve(to: P(0.5090, 0.9564), control1: P(0.5031, 0.9584), control2: P(0.5062, 0.9577))
        p.addCurve(to: P(0.5162, 0.9507), control1: P(0.5118, 0.9550), control2: P(0.5143, 0.9531))
        p.addCurve(to: P(0.5203, 0.9425), control1: P(0.5182, 0.9483), control2: P(0.5196, 0.9455))
        p.addCurve(to: P(0.5485, 0.8590), control1: P(0.5275, 0.9139), control2: P(0.5369, 0.8862))
        p.addCurve(to: P(0.6736, 0.6736), control1: P(0.5780, 0.7898), control2: P(0.6205, 0.7268))
        p.addCurve(to: P(0.7978, 0.5790), control1: P(0.7106, 0.6367), control2: P(0.7523, 0.6048))
        p.addCurve(to: P(0.9425, 0.5203), control1: P(0.8432, 0.5531), control2: P(0.8918, 0.5334))
        p.addCurve(to: P(0.9506, 0.5162), control1: P(0.9455, 0.5196), control2: P(0.9482, 0.5182))
        p.addCurve(to: P(0.9563, 0.5090), control1: P(0.9530, 0.5142), control2: P(0.9549, 0.5118))
        p.addCurve(to: P(0.9583, 0.5000), control1: P(0.9576, 0.5062), control2: P(0.9583, 0.5031))
        p.addCurve(to: P(0.9563, 0.4911), control1: P(0.9583, 0.4969), control2: P(0.9576, 0.4939))
        p.addCurve(to: P(0.9506, 0.4839), control1: P(0.9549, 0.4883), control2: P(0.9530, 0.4858))
        p.addCurve(to: P(0.9425, 0.4797), control1: P(0.9482, 0.4819), control2: P(0.9455, 0.4805))
        p.addCurve(to: P(0.8590, 0.4515), control1: P(0.9139, 0.4725), control2: P(0.8860, 0.4631))
        p.closeSubpath()
        return p
    }()

    static let cursor: SwiftUI.Path = {
        var p = SwiftUI.Path()
        p.move(to: P(0.9211, 0.2367))
        p.addLine(to: P(0.5208, 0.0056))
        p.addCurve(to: P(0.5000, 0.0001), control1: P(0.5145, 0.0020), control2: P(0.5073, 0.0001))
        p.addCurve(to: P(0.4793, 0.0056), control1: P(0.4927, 0.0001), control2: P(0.4856, 0.0020))
        p.addLine(to: P(0.0789, 0.2367))
        p.addCurve(to: P(0.0661, 0.2495), control1: P(0.0736, 0.2397), control2: P(0.0692, 0.2442))
        p.addCurve(to: P(0.0614, 0.2669), control1: P(0.0630, 0.2548), control2: P(0.0614, 0.2608))
        p.addLine(to: P(0.0614, 0.7330))
        p.addCurve(to: P(0.0789, 0.7633), control1: P(0.0614, 0.7455), control2: P(0.0681, 0.7570))
        p.addLine(to: P(0.4792, 0.9944))
        p.addCurve(to: P(0.5000, 1.0000), control1: P(0.4855, 0.9981), control2: P(0.4927, 1.0000))
        p.addCurve(to: P(0.5208, 0.9944), control1: P(0.5073, 1.0000), control2: P(0.5145, 0.9981))
        p.addLine(to: P(0.9211, 0.7633))
        p.addCurve(to: P(0.9339, 0.7505), control1: P(0.9264, 0.7602), control2: P(0.9309, 0.7558))
        p.addCurve(to: P(0.9386, 0.7330), control1: P(0.9370, 0.7452), control2: P(0.9386, 0.7391))
        p.addLine(to: P(0.9386, 0.2670))
        p.addCurve(to: P(0.9339, 0.2495), control1: P(0.9386, 0.2608), control2: P(0.9370, 0.2548))
        p.addCurve(to: P(0.9211, 0.2367), control1: P(0.9308, 0.2442), control2: P(0.9264, 0.2398))
        p.closeSubpath()
        p.move(to: P(0.8960, 0.2857))
        p.addLine(to: P(0.5095, 0.9550))
        p.addCurve(to: P(0.5000, 0.9525), control1: P(0.5069, 0.9595), control2: P(0.5000, 0.9577))
        p.addLine(to: P(0.5000, 0.5142))
        p.addCurve(to: P(0.4967, 0.5019), control1: P(0.5000, 0.5099), control2: P(0.4989, 0.5056))
        p.addCurve(to: P(0.4877, 0.4929), control1: P(0.4945, 0.4982), control2: P(0.4914, 0.4951))
        p.addLine(to: P(0.1081, 0.2737))
        p.addCurve(to: P(0.1107, 0.2643), control1: P(0.1037, 0.2712), control2: P(0.1055, 0.2643))
        p.addLine(to: P(0.8836, 0.2643))
        p.addCurve(to: P(0.8960, 0.2857), control1: P(0.8946, 0.2643), control2: P(0.9015, 0.2762))
        p.closeSubpath()
        return p
    }()

    static let qwen: SwiftUI.Path = {
        var p = SwiftUI.Path()
        p.move(to: P(0.5252, 0.0558))
        p.addCurve(to: P(0.5741, 0.1423), control1: P(0.5415, 0.0846), control2: P(0.5578, 0.1134))
        p.addCurve(to: P(0.5758, 0.1443), control1: P(0.5745, 0.1431), control2: P(0.5751, 0.1437))
        p.addCurve(to: P(0.5780, 0.1456), control1: P(0.5764, 0.1449), control2: P(0.5772, 0.1453))
        p.addCurve(to: P(0.5806, 0.1461), control1: P(0.5789, 0.1459), control2: P(0.5797, 0.1461))
        p.addLine(to: P(0.8120, 0.1461))
        p.addCurve(to: P(0.8305, 0.1597), control1: P(0.8192, 0.1461), control2: P(0.8254, 0.1507))
        p.addLine(to: P(0.8911, 0.2668))
        p.addCurve(to: P(0.8921, 0.3017), control1: P(0.8990, 0.2808), control2: P(0.9011, 0.2867))
        p.addCurve(to: P(0.8605, 0.3558), control1: P(0.8813, 0.3196), control2: P(0.8708, 0.3377))
        p.addLine(to: P(0.8452, 0.3833))
        p.addCurve(to: P(0.8435, 0.4046), control1: P(0.8407, 0.3914), control2: P(0.8359, 0.3949))
        p.addLine(to: P(0.9540, 0.5978))
        p.addCurve(to: P(0.9522, 0.6299), control1: P(0.9612, 0.6103), control2: P(0.9586, 0.6184))
        p.addCurve(to: P(0.8966, 0.7274), control1: P(0.9340, 0.6626), control2: P(0.9155, 0.6950))
        p.addCurve(to: P(0.8683, 0.7428), control1: P(0.8900, 0.7387), control2: P(0.8819, 0.7430))
        p.addCurve(to: P(0.7713, 0.7435), control1: P(0.8359, 0.7421), control2: P(0.8036, 0.7424))
        p.addCurve(to: P(0.7693, 0.7441), control1: P(0.7706, 0.7435), control2: P(0.7699, 0.7437))
        p.addCurve(to: P(0.7679, 0.7455), control1: P(0.7687, 0.7444), control2: P(0.7683, 0.7449))
        p.addCurve(to: P(0.6552, 0.9430), control1: P(0.7307, 0.8116), control2: P(0.6931, 0.8774))
        p.addCurve(to: P(0.6250, 0.9582), control1: P(0.6482, 0.9553), control2: P(0.6394, 0.9582))
        p.addCurve(to: P(0.4993, 0.9583), control1: P(0.5835, 0.9583), control2: P(0.5416, 0.9584))
        p.addCurve(to: P(0.4916, 0.9569), control1: P(0.4967, 0.9583), control2: P(0.4941, 0.9578))
        p.addCurve(to: P(0.4849, 0.9530), control1: P(0.4892, 0.9560), control2: P(0.4869, 0.9547))
        p.addCurve(to: P(0.4799, 0.9470), control1: P(0.4829, 0.9513), control2: P(0.4812, 0.9493))
        p.addLine(to: P(0.4243, 0.8502))
        p.addCurve(to: P(0.4234, 0.8491), control1: P(0.4241, 0.8498), control2: P(0.4238, 0.8494))
        p.addCurve(to: P(0.4222, 0.8484), control1: P(0.4231, 0.8488), control2: P(0.4227, 0.8485))
        p.addCurve(to: P(0.4208, 0.8482), control1: P(0.4218, 0.8482), control2: P(0.4213, 0.8482))
        p.addLine(to: P(0.2076, 0.8482))
        p.addCurve(to: P(0.1740, 0.8443), control1: P(0.1957, 0.8494), control2: P(0.1845, 0.8481))
        p.addLine(to: P(0.1073, 0.7289))
        p.addCurve(to: P(0.1042, 0.7177), control1: P(0.1053, 0.7255), control2: P(0.1042, 0.7216))
        p.addCurve(to: P(0.1072, 0.7064), control1: P(0.1042, 0.7137), control2: P(0.1052, 0.7098))
        p.addLine(to: P(0.1575, 0.6181))
        p.addCurve(to: P(0.1586, 0.6140), control1: P(0.1582, 0.6168), control2: P(0.1586, 0.6154))
        p.addCurve(to: P(0.1575, 0.6099), control1: P(0.1586, 0.6125), control2: P(0.1582, 0.6111))
        p.addCurve(to: P(0.0793, 0.4735), control1: P(0.1313, 0.5645), control2: P(0.1052, 0.5191))
        p.addLine(to: P(0.0464, 0.4154))
        p.addCurve(to: P(0.0504, 0.3752), control1: P(0.0398, 0.4025), control2: P(0.0392, 0.3948))
        p.addCurve(to: P(0.1082, 0.2737), control1: P(0.0698, 0.3413), control2: P(0.0890, 0.3075))
        p.addCurve(to: P(0.1325, 0.2598), control1: P(0.1137, 0.2640), control2: P(0.1208, 0.2598))
        p.addCurve(to: P(0.2404, 0.2597), control1: P(0.1685, 0.2596), control2: P(0.2044, 0.2596))
        p.addCurve(to: P(0.2421, 0.2594), control1: P(0.2410, 0.2597), control2: P(0.2416, 0.2596))
        p.addCurve(to: P(0.2437, 0.2585), control1: P(0.2427, 0.2592), control2: P(0.2432, 0.2589))
        p.addCurve(to: P(0.2448, 0.2571), control1: P(0.2441, 0.2581), control2: P(0.2445, 0.2576))
        p.addLine(to: P(0.3618, 0.0531))
        p.addCurve(to: P(0.3663, 0.0477), control1: P(0.3629, 0.0511), control2: P(0.3645, 0.0492))
        p.addCurve(to: P(0.3724, 0.0441), control1: P(0.3681, 0.0462), control2: P(0.3701, 0.0450))
        p.addCurve(to: P(0.3793, 0.0429), control1: P(0.3746, 0.0433), control2: P(0.3770, 0.0429))
        p.addCurve(to: P(0.4453, 0.0426), control1: P(0.4012, 0.0428), control2: P(0.4232, 0.0429))
        p.addLine(to: P(0.4877, 0.0417))
        p.addCurve(to: P(0.5252, 0.0558), control1: P(0.5019, 0.0415), control2: P(0.5178, 0.0430))
        p.closeSubpath()
        p.move(to: P(0.3822, 0.0726))
        p.addCurve(to: P(0.3813, 0.0728), control1: P(0.3819, 0.0726), control2: P(0.3816, 0.0727))
        p.addCurve(to: P(0.3806, 0.0732), control1: P(0.3810, 0.0729), control2: P(0.3808, 0.0730))
        p.addCurve(to: P(0.3800, 0.0739), control1: P(0.3803, 0.0734), control2: P(0.3801, 0.0736))
        p.addLine(to: P(0.2606, 0.2828))
        p.addCurve(to: P(0.2582, 0.2852), control1: P(0.2600, 0.2838), control2: P(0.2592, 0.2846))
        p.addCurve(to: P(0.2550, 0.2861), control1: P(0.2572, 0.2858), control2: P(0.2561, 0.2861))
        p.addLine(to: P(0.1355, 0.2861))
        p.addCurve(to: P(0.1338, 0.2892), control1: P(0.1332, 0.2861), control2: P(0.1326, 0.2871))
        p.addLine(to: P(0.3759, 0.7123))
        p.addCurve(to: P(0.3745, 0.7150), control1: P(0.3770, 0.7141), control2: P(0.3765, 0.7149))
        p.addLine(to: P(0.2580, 0.7156))
        p.addCurve(to: P(0.2547, 0.7161), control1: P(0.2569, 0.7155), control2: P(0.2558, 0.7157))
        p.addCurve(to: P(0.2518, 0.7178), control1: P(0.2536, 0.7165), control2: P(0.2527, 0.7170))
        p.addCurve(to: P(0.2497, 0.7204), control1: P(0.2509, 0.7185), control2: P(0.2502, 0.7194))
        p.addLine(to: P(0.1947, 0.8167))
        p.addCurve(to: P(0.1975, 0.8216), control1: P(0.1929, 0.8199), control2: P(0.1938, 0.8216))
        p.addLine(to: P(0.4357, 0.8219))
        p.addCurve(to: P(0.4400, 0.8245), control1: P(0.4376, 0.8219), control2: P(0.4390, 0.8227))
        p.addLine(to: P(0.4985, 0.9267))
        p.addCurve(to: P(0.5043, 0.9267), control1: P(0.5004, 0.9301), control2: P(0.5023, 0.9301))
        p.addLine(to: P(0.7129, 0.5617))
        p.addLine(to: P(0.7455, 0.5041))
        p.addCurve(to: P(0.7461, 0.5034), control1: P(0.7457, 0.5038), control2: P(0.7459, 0.5036))
        p.addCurve(to: P(0.7470, 0.5030), control1: P(0.7464, 0.5032), control2: P(0.7467, 0.5031))
        p.addCurve(to: P(0.7480, 0.5030), control1: P(0.7473, 0.5029), control2: P(0.7477, 0.5029))
        p.addCurve(to: P(0.7489, 0.5034), control1: P(0.7483, 0.5031), control2: P(0.7486, 0.5032))
        p.addCurve(to: P(0.7495, 0.5041), control1: P(0.7491, 0.5036), control2: P(0.7493, 0.5038))
        p.addLine(to: P(0.8088, 0.6095))
        p.addCurve(to: P(0.8100, 0.6109), control1: P(0.8091, 0.6101), control2: P(0.8095, 0.6105))
        p.addCurve(to: P(0.8115, 0.6118), control1: P(0.8104, 0.6113), control2: P(0.8110, 0.6116))
        p.addCurve(to: P(0.8133, 0.6121), control1: P(0.8121, 0.6120), control2: P(0.8127, 0.6121))
        p.addLine(to: P(0.9284, 0.6113))
        p.addCurve(to: P(0.9290, 0.6112), control1: P(0.9286, 0.6113), control2: P(0.9288, 0.6113))
        p.addCurve(to: P(0.9295, 0.6109), control1: P(0.9292, 0.6111), control2: P(0.9293, 0.6110))
        p.addCurve(to: P(0.9299, 0.6105), control1: P(0.9296, 0.6108), control2: P(0.9298, 0.6106))
        p.addCurve(to: P(0.9301, 0.6096), control1: P(0.9300, 0.6102), control2: P(0.9301, 0.6099))
        p.addCurve(to: P(0.9299, 0.6088), control1: P(0.9301, 0.6093), control2: P(0.9300, 0.6090))
        p.addLine(to: P(0.8090, 0.3969))
        p.addCurve(to: P(0.8085, 0.3953), control1: P(0.8088, 0.3964), control2: P(0.8086, 0.3959))
        p.addCurve(to: P(0.8085, 0.3937), control1: P(0.8084, 0.3948), control2: P(0.8084, 0.3942))
        p.addCurve(to: P(0.8090, 0.3922), control1: P(0.8086, 0.3932), control2: P(0.8088, 0.3926))
        p.addLine(to: P(0.8212, 0.3710))
        p.addLine(to: P(0.8679, 0.2887))
        p.addCurve(to: P(0.8665, 0.2861), control1: P(0.8689, 0.2870), control2: P(0.8684, 0.2861))
        p.addLine(to: P(0.3833, 0.2861))
        p.addCurve(to: P(0.3815, 0.2829), control1: P(0.3809, 0.2861), control2: P(0.3803, 0.2850))
        p.addLine(to: P(0.4413, 0.1785))
        p.addCurve(to: P(0.4419, 0.1770), control1: P(0.4416, 0.1780), control2: P(0.4418, 0.1775))
        p.addCurve(to: P(0.4419, 0.1753), control1: P(0.4420, 0.1764), control2: P(0.4420, 0.1758))
        p.addCurve(to: P(0.4413, 0.1737), control1: P(0.4418, 0.1747), control2: P(0.4416, 0.1742))
        p.addLine(to: P(0.3844, 0.0739))
        p.addCurve(to: P(0.3838, 0.0732), control1: P(0.3842, 0.0737), control2: P(0.3840, 0.0734))
        p.addCurve(to: P(0.3830, 0.0728), control1: P(0.3836, 0.0730), control2: P(0.3833, 0.0729))
        p.addCurve(to: P(0.3822, 0.0726), control1: P(0.3828, 0.0727), control2: P(0.3825, 0.0726))
        p.closeSubpath()
        p.move(to: P(0.6442, 0.4068))
        p.addCurve(to: P(0.6457, 0.4093), control1: P(0.6462, 0.4068), control2: P(0.6467, 0.4076))
        p.addLine(to: P(0.6110, 0.4703))
        p.addLine(to: P(0.5021, 0.6614))
        p.addCurve(to: P(0.5016, 0.6620), control1: P(0.5020, 0.6616), control2: P(0.5018, 0.6618))
        p.addCurve(to: P(0.5009, 0.6624), control1: P(0.5014, 0.6622), control2: P(0.5011, 0.6624))
        p.addCurve(to: P(0.5000, 0.6626), control1: P(0.5006, 0.6625), control2: P(0.5003, 0.6626))
        p.addCurve(to: P(0.4988, 0.6623), control1: P(0.4996, 0.6626), control2: P(0.4992, 0.6625))
        p.addCurve(to: P(0.4980, 0.6614), control1: P(0.4985, 0.6620), control2: P(0.4982, 0.6617))
        p.addLine(to: P(0.3541, 0.4100))
        p.addCurve(to: P(0.3553, 0.4078), control1: P(0.3533, 0.4086), control2: P(0.3537, 0.4079))
        p.addLine(to: P(0.3642, 0.4073))
        p.addLine(to: P(0.6443, 0.4068))
        p.closeSubpath()
        return p
    }()

    static let kimi: SwiftUI.Path = {
        var p = SwiftUI.Path()
        p.move(to: P(0.0438, 0.7048))
        p.addLine(to: P(0.4413, 0.8112))
        p.addCurve(to: P(0.4438, 0.8959), control1: P(0.4408, 0.8394), control2: P(0.4416, 0.8677))
        p.addLine(to: P(0.6920, 0.9623))
        p.addCurve(to: P(0.4592, 0.9983), control1: P(0.6184, 0.9926), control2: P(0.5386, 1.0050))
        p.addLine(to: P(0.4517, 0.9976))
        p.addLine(to: P(0.4499, 0.9975))
        p.addLine(to: P(0.4464, 0.9971))
        p.addLine(to: P(0.4425, 0.9967))
        p.addCurve(to: P(0.4359, 0.9958), control1: P(0.4403, 0.9964), control2: P(0.4381, 0.9961))
        p.addLine(to: P(0.4315, 0.9952))
        p.addLine(to: P(0.4269, 0.9946))
        p.addCurve(to: P(0.4135, 0.9925), control1: P(0.4224, 0.9939), control2: P(0.4180, 0.9932))
        p.addLine(to: P(0.4118, 0.9921))
        p.addLine(to: P(0.4087, 0.9916))
        p.addLine(to: P(0.4042, 0.9908))
        p.addLine(to: P(0.4013, 0.9901))
        p.addLine(to: P(0.3974, 0.9893))
        p.addLine(to: P(0.3943, 0.9887))
        p.addLine(to: P(0.3903, 0.9878))
        p.addLine(to: P(0.3863, 0.9869))
        p.addLine(to: P(0.3824, 0.9860))
        p.addLine(to: P(0.3795, 0.9853))
        p.addLine(to: P(0.3759, 0.9843))
        p.addLine(to: P(0.3721, 0.9833))
        p.addLine(to: P(0.3682, 0.9823))
        p.addLine(to: P(0.3648, 0.9813))
        p.addLine(to: P(0.3602, 0.9801))
        p.addLine(to: P(0.3576, 0.9793))
        p.addLine(to: P(0.3541, 0.9782))
        p.addLine(to: P(0.3503, 0.9770))
        p.addLine(to: P(0.3459, 0.9756))
        p.addLine(to: P(0.3435, 0.9748))
        p.addLine(to: P(0.3401, 0.9738))
        p.addLine(to: P(0.3364, 0.9725))
        p.addLine(to: P(0.3336, 0.9715))
        p.addCurve(to: P(0.3318, 0.9708), control1: P(0.3330, 0.9713), control2: P(0.3324, 0.9710))
        p.addLine(to: P(0.3290, 0.9698))
        p.addLine(to: P(0.3248, 0.9683))
        p.addLine(to: P(0.3224, 0.9673))
        p.addLine(to: P(0.3190, 0.9661))
        p.addLine(to: P(0.3154, 0.9646))
        p.addLine(to: P(0.3118, 0.9632))
        p.addLine(to: P(0.3085, 0.9618))
        p.addLine(to: P(0.3045, 0.9602))
        p.addLine(to: P(0.3019, 0.9590))
        p.addLine(to: P(0.2993, 0.9579))
        p.addCurve(to: P(0.2975, 0.9571), control1: P(0.2987, 0.9576), control2: P(0.2981, 0.9574))
        p.addLine(to: P(0.2948, 0.9559))
        p.addLine(to: P(0.2905, 0.9539))
        p.addLine(to: P(0.2883, 0.9529))
        p.addLine(to: P(0.2843, 0.9510))
        p.addLine(to: P(0.2818, 0.9498))
        p.addLine(to: P(0.2783, 0.9481))
        p.addLine(to: P(0.2747, 0.9463))
        p.addLine(to: P(0.2708, 0.9443))
        p.addLine(to: P(0.2686, 0.9432))
        p.addLine(to: P(0.2643, 0.9409))
        p.addLine(to: P(0.2620, 0.9396))
        p.addLine(to: P(0.2595, 0.9383))
        p.addCurve(to: P(0.2576, 0.9372), control1: P(0.2589, 0.9379), control2: P(0.2583, 0.9376))
        p.addLine(to: P(0.2537, 0.9350))
        p.addLine(to: P(0.2512, 0.9336))
        p.addLine(to: P(0.2491, 0.9323))
        p.addLine(to: P(0.2461, 0.9306))
        p.addLine(to: P(0.2427, 0.9285))
        p.addLine(to: P(0.2388, 0.9262))
        p.addLine(to: P(0.2366, 0.9249))
        p.addLine(to: P(0.2331, 0.9227))
        p.addLine(to: P(0.2306, 0.9210))
        p.addLine(to: P(0.2273, 0.9190))
        p.addLine(to: P(0.2244, 0.9170))
        p.addLine(to: P(0.2222, 0.9155))
        p.addCurve(to: P(0.2199, 0.9140), control1: P(0.2214, 0.9150), control2: P(0.2207, 0.9145))
        p.addLine(to: P(0.2181, 0.9128))
        p.addLine(to: P(0.2163, 0.9115))
        p.addCurve(to: P(0.2146, 0.9104), control1: P(0.2157, 0.9112), control2: P(0.2151, 0.9108))
        p.addLine(to: P(0.2122, 0.9087))
        p.addLine(to: P(0.2090, 0.9065))
        p.addLine(to: P(0.2062, 0.9044))
        p.addLine(to: P(0.2031, 0.9021))
        p.addLine(to: P(0.2008, 0.9004))
        p.addLine(to: P(0.1976, 0.8980))
        p.addLine(to: P(0.1944, 0.8955))
        p.addLine(to: P(0.1908, 0.8928))
        p.addLine(to: P(0.1890, 0.8913))
        p.addLine(to: P(0.1863, 0.8891))
        p.addLine(to: P(0.1832, 0.8866))
        p.addLine(to: P(0.1795, 0.8836))
        p.addLine(to: P(0.1776, 0.8820))
        p.addLine(to: P(0.1757, 0.8803))
        p.addCurve(to: P(0.1739, 0.8788), control1: P(0.1751, 0.8798), control2: P(0.1745, 0.8793))
        p.addLine(to: P(0.1720, 0.8771))
        p.addLine(to: P(0.1695, 0.8749))
        p.addLine(to: P(0.1665, 0.8723))
        p.addLine(to: P(0.1637, 0.8698))
        p.addLine(to: P(0.1611, 0.8674))
        p.addLine(to: P(0.1583, 0.8648))
        p.addLine(to: P(0.1561, 0.8628))
        p.addLine(to: P(0.1525, 0.8593))
        p.addCurve(to: P(0.1483, 0.8552), control1: P(0.1511, 0.8579), control2: P(0.1497, 0.8566))
        p.addLine(to: P(0.1471, 0.8540))
        p.addLine(to: P(0.1454, 0.8523))
        p.addLine(to: P(0.1425, 0.8494))
        p.addLine(to: P(0.1405, 0.8473))
        p.addLine(to: P(0.1384, 0.8450))
        p.addCurve(to: P(0.1314, 0.8376), control1: P(0.1360, 0.8426), control2: P(0.1337, 0.8401))
        p.addLine(to: P(0.1280, 0.8339))
        p.addLine(to: P(0.1255, 0.8310))
        p.addLine(to: P(0.1225, 0.8277))
        p.addLine(to: P(0.1208, 0.8256))
        p.addLine(to: P(0.1185, 0.8230))
        p.addLine(to: P(0.1161, 0.8202))
        p.addLine(to: P(0.1142, 0.8179))
        p.addCurve(to: P(0.1131, 0.8165), control1: P(0.1138, 0.8174), control2: P(0.1135, 0.8170))
        p.addLine(to: P(0.1112, 0.8142))
        p.addLine(to: P(0.1085, 0.8108))
        p.addLine(to: P(0.1068, 0.8086))
        p.addLine(to: P(0.1047, 0.8060))
        p.addLine(to: P(0.1038, 0.8049))
        p.addCurve(to: P(0.0438, 0.7048), control1: P(0.0800, 0.7740), control2: P(0.0599, 0.7404))
        p.closeSubpath()
        p.move(to: P(0.0013, 0.4634))
        p.addLine(to: P(0.4744, 0.5900))
        p.addCurve(to: P(0.4548, 0.6737), control1: P(0.4665, 0.6175), control2: P(0.4599, 0.6455))
        p.addLine(to: P(0.9055, 0.7943))
        p.addCurve(to: P(0.8287, 0.8779), control1: P(0.8832, 0.8250), control2: P(0.8574, 0.8530))
        p.addLine(to: P(0.0274, 0.6635))
        p.addLine(to: P(0.0267, 0.6615))
        p.addLine(to: P(0.0252, 0.6572))
        p.addCurve(to: P(0.0232, 0.6508), control1: P(0.0245, 0.6551), control2: P(0.0238, 0.6530))
        p.addLine(to: P(0.0229, 0.6499))
        p.addCurve(to: P(0.0142, 0.6190), control1: P(0.0197, 0.6397), control2: P(0.0168, 0.6294))
        p.addLine(to: P(0.0130, 0.6138))
        p.addLine(to: P(0.0122, 0.6104))
        p.addLine(to: P(0.0114, 0.6064))
        p.addLine(to: P(0.0106, 0.6030))
        p.addLine(to: P(0.0099, 0.5993))
        p.addLine(to: P(0.0092, 0.5958))
        p.addLine(to: P(0.0084, 0.5918))
        p.addCurve(to: P(0.0055, 0.5741), control1: P(0.0073, 0.5860), control2: P(0.0063, 0.5800))
        p.addLine(to: P(0.0047, 0.5692))
        p.addLine(to: P(0.0043, 0.5657))
        p.addLine(to: P(0.0037, 0.5615))
        p.addCurve(to: P(0.0030, 0.5548), control1: P(0.0035, 0.5592), control2: P(0.0032, 0.5570))
        p.addLine(to: P(0.0027, 0.5528))
        p.addCurve(to: P(0.0013, 0.4634), control1: P(-0.0004, 0.5231), control2: P(-0.0008, 0.4932))
        p.closeSubpath()
        p.move(to: P(0.0677, 0.2488))
        p.addLine(to: P(0.5655, 0.3820))
        p.addCurve(to: P(0.5235, 0.4601), control1: P(0.5502, 0.4072), control2: P(0.5362, 0.4333))
        p.addLine(to: P(0.9941, 0.5860))
        p.addCurve(to: P(0.9663, 0.6846), control1: P(0.9882, 0.6202), control2: P(0.9788, 0.6532))
        p.addLine(to: P(0.4850, 0.5558))
        p.addLine(to: P(0.0052, 0.4275))
        p.addLine(to: P(0.0058, 0.4233))
        p.addLine(to: P(0.0061, 0.4213))
        p.addLine(to: P(0.0065, 0.4185))
        p.addLine(to: P(0.0072, 0.4149))
        p.addLine(to: P(0.0079, 0.4108))
        p.addCurve(to: P(0.0116, 0.3924), control1: P(0.0090, 0.4046), control2: P(0.0103, 0.3985))
        p.addLine(to: P(0.0128, 0.3872))
        p.addLine(to: P(0.0136, 0.3837))
        p.addLine(to: P(0.0146, 0.3796))
        p.addCurve(to: P(0.0175, 0.3685), control1: P(0.0155, 0.3759), control2: P(0.0165, 0.3721))
        p.addLine(to: P(0.0187, 0.3642))
        p.addLine(to: P(0.0196, 0.3607))
        p.addLine(to: P(0.0209, 0.3566))
        p.addLine(to: P(0.0219, 0.3532))
        p.addLine(to: P(0.0232, 0.3492))
        p.addLine(to: P(0.0243, 0.3457))
        p.addLine(to: P(0.0255, 0.3418))
        p.addCurve(to: P(0.0676, 0.2488), control1: P(0.0363, 0.3094), control2: P(0.0504, 0.2783))
        p.closeSubpath()
        p.move(to: P(0.2528, 0.0655))
        p.addLine(to: P(0.7230, 0.1913))
        p.addCurve(to: P(0.6527, 0.2630), control1: P(0.6982, 0.2138), control2: P(0.6747, 0.2377))
        p.addLine(to: P(0.9786, 0.3502))
        p.addCurve(to: P(1.0000, 0.4612), control1: P(0.9898, 0.3857), control2: P(0.9970, 0.4228))
        p.addLine(to: P(0.0877, 0.2172))
        p.addLine(to: P(0.0896, 0.2145))
        p.addLine(to: P(0.0907, 0.2128))
        p.addLine(to: P(0.0924, 0.2105))
        p.addLine(to: P(0.0943, 0.2078))
        p.addLine(to: P(0.0966, 0.2047))
        p.addLine(to: P(0.0989, 0.2017))
        p.addLine(to: P(0.1015, 0.1981))
        p.addLine(to: P(0.1036, 0.1954))
        p.addLine(to: P(0.1060, 0.1923))
        p.addLine(to: P(0.1083, 0.1894))
        p.addLine(to: P(0.1108, 0.1863))
        p.addLine(to: P(0.1131, 0.1835))
        p.addLine(to: P(0.1158, 0.1802))
        p.addLine(to: P(0.1180, 0.1775))
        p.addLine(to: P(0.1208, 0.1743))
        p.addLine(to: P(0.1230, 0.1718))
        p.addLine(to: P(0.1260, 0.1684))
        p.addLine(to: P(0.1282, 0.1659))
        p.addLine(to: P(0.1310, 0.1628))
        p.addLine(to: P(0.1332, 0.1604))
        p.addLine(to: P(0.1363, 0.1571))
        p.addLine(to: P(0.1387, 0.1546))
        p.addLine(to: P(0.1413, 0.1518))
        p.addLine(to: P(0.1483, 0.1447))
        p.addLine(to: P(0.1525, 0.1407))
        p.addLine(to: P(0.1550, 0.1383))
        p.addLine(to: P(0.1581, 0.1354))
        p.addCurve(to: P(0.2528, 0.0655), control1: P(0.1868, 0.1085), control2: P(0.2186, 0.0850))
        p.closeSubpath()
        p.move(to: P(0.5007, 0.0000))
        p.addLine(to: P(0.5047, 0.0000))
        p.addLine(to: P(0.5082, 0.0000))
        p.addLine(to: P(0.5110, 0.0001))
        p.addLine(to: P(0.5133, 0.0002))
        p.addLine(to: P(0.5161, 0.0003))
        p.addLine(to: P(0.5180, 0.0003))
        p.addLine(to: P(0.5212, 0.0004))
        p.addLine(to: P(0.5232, 0.0005))
        p.addLine(to: P(0.5257, 0.0006))
        p.addLine(to: P(0.5279, 0.0007))
        p.addLine(to: P(0.5315, 0.0009))
        p.addLine(to: P(0.5359, 0.0012))
        p.addLine(to: P(0.5419, 0.0017))
        p.addLine(to: P(0.5456, 0.0020))
        p.addLine(to: P(0.5474, 0.0021))
        p.addLine(to: P(0.5506, 0.0025))
        p.addLine(to: P(0.5540, 0.0028))
        p.addLine(to: P(0.5560, 0.0030))
        p.addLine(to: P(0.5603, 0.0035))
        p.addLine(to: P(0.5623, 0.0038))
        p.addLine(to: P(0.5668, 0.0043))
        p.addLine(to: P(0.5702, 0.0047))
        p.addLine(to: P(0.5720, 0.0050))
        p.addLine(to: P(0.5747, 0.0054))
        p.addLine(to: P(0.5833, 0.0067))
        p.addLine(to: P(0.5862, 0.0073))
        p.addLine(to: P(0.5889, 0.0077))
        p.addLine(to: P(0.5948, 0.0088))
        p.addLine(to: P(0.5986, 0.0095))
        p.addLine(to: P(0.6032, 0.0105))
        p.addLine(to: P(0.6051, 0.0109))
        p.addLine(to: P(0.6082, 0.0115))
        p.addLine(to: P(0.6099, 0.0120))
        p.addLine(to: P(0.6125, 0.0125))
        p.addLine(to: P(0.6142, 0.0129))
        p.addLine(to: P(0.6170, 0.0135))
        p.addLine(to: P(0.6190, 0.0140))
        p.addLine(to: P(0.6220, 0.0148))
        p.addLine(to: P(0.6260, 0.0158))
        p.addLine(to: P(0.6306, 0.0170))
        p.addLine(to: P(0.6353, 0.0183))
        p.addLine(to: P(0.6400, 0.0196))
        p.addLine(to: P(0.6421, 0.0202))
        p.addLine(to: P(0.6450, 0.0210))
        p.addLine(to: P(0.6483, 0.0220))
        p.addLine(to: P(0.6513, 0.0230))
        p.addLine(to: P(0.6534, 0.0237))
        p.addLine(to: P(0.6555, 0.0243))
        p.addLine(to: P(0.6587, 0.0254))
        p.addLine(to: P(0.6628, 0.0268))
        p.addLine(to: P(0.6670, 0.0283))
        p.addLine(to: P(0.6690, 0.0290))
        p.addLine(to: P(0.6717, 0.0299))
        p.addLine(to: P(0.6756, 0.0313))
        p.addLine(to: P(0.6802, 0.0330))
        p.addLine(to: P(0.6850, 0.0349))
        p.addLine(to: P(0.6892, 0.0366))
        p.addLine(to: P(0.6911, 0.0374))
        p.addLine(to: P(0.6936, 0.0384))
        p.addLine(to: P(0.6953, 0.0392))
        p.addLine(to: P(0.6980, 0.0403))
        p.addLine(to: P(0.6996, 0.0410))
        p.addLine(to: P(0.7020, 0.0420))
        p.addLine(to: P(0.7066, 0.0440))
        p.addLine(to: P(0.7107, 0.0460))
        p.addLine(to: P(0.7138, 0.0474))
        p.addLine(to: P(0.7170, 0.0489))
        p.addLine(to: P(0.7195, 0.0501))
        p.addLine(to: P(0.7233, 0.0520))
        p.addLine(to: P(0.7271, 0.0539))
        p.addLine(to: P(0.7313, 0.0560))
        p.addLine(to: P(0.7335, 0.0572))
        p.addLine(to: P(0.7356, 0.0583))
        p.addLine(to: P(0.7375, 0.0593))
        p.addLine(to: P(0.7400, 0.0607))
        p.addLine(to: P(0.7417, 0.0616))
        p.addLine(to: P(0.7439, 0.0628))
        p.addLine(to: P(0.7475, 0.0649))
        p.addLine(to: P(0.7520, 0.0674))
        p.addLine(to: P(0.7556, 0.0695))
        p.addLine(to: P(0.7580, 0.0709))
        p.addLine(to: P(0.7602, 0.0723))
        p.addLine(to: P(0.7642, 0.0747))
        p.addLine(to: P(0.7678, 0.0770))
        p.addLine(to: P(0.7719, 0.0796))
        p.addLine(to: P(0.7734, 0.0806))
        p.addLine(to: P(0.7761, 0.0823))
        p.addLine(to: P(0.7796, 0.0846))
        p.addLine(to: P(0.7812, 0.0858))
        p.addLine(to: P(0.7838, 0.0875))
        p.addLine(to: P(0.7864, 0.0893))
        p.addLine(to: P(0.7874, 0.0900))
        p.addCurve(to: P(0.7941, 0.0948), control1: P(0.7896, 0.0915), control2: P(0.7919, 0.0931))
        p.addLine(to: P(0.7975, 0.0973))
        p.addLine(to: P(0.8003, 0.0993))
        p.addLine(to: P(0.8026, 0.1010))
        p.addLine(to: P(0.8062, 0.1038))
        p.addLine(to: P(0.8096, 0.1064))
        p.addLine(to: P(0.8112, 0.1077))
        p.addLine(to: P(0.8133, 0.1094))
        p.addLine(to: P(0.8169, 0.1123))
        p.addLine(to: P(0.8202, 0.1150))
        p.addLine(to: P(0.8237, 0.1179))
        p.addCurve(to: P(0.9033, 0.2025), control1: P(0.8534, 0.1429), control2: P(0.8801, 0.1714))
        p.addLine(to: P(0.3009, 0.0414))
        p.addLine(to: P(0.3035, 0.0403))
        p.addLine(to: P(0.3062, 0.0391))
        p.addLine(to: P(0.3096, 0.0377))
        p.addLine(to: P(0.3132, 0.0362))
        p.addCurve(to: P(0.3274, 0.0308), control1: P(0.3179, 0.0344), control2: P(0.3226, 0.0325))
        p.addLine(to: P(0.3314, 0.0293))
        p.addLine(to: P(0.3353, 0.0280))
        p.addLine(to: P(0.3388, 0.0267))
        p.addLine(to: P(0.3428, 0.0254))
        p.addCurve(to: P(0.3538, 0.0219), control1: P(0.3464, 0.0242), control2: P(0.3501, 0.0230))
        p.addLine(to: P(0.3575, 0.0207))
        p.addLine(to: P(0.3611, 0.0197))
        p.addLine(to: P(0.3654, 0.0185))
        p.addLine(to: P(0.3689, 0.0175))
        p.addLine(to: P(0.3731, 0.0164))
        p.addLine(to: P(0.3767, 0.0154))
        p.addLine(to: P(0.3804, 0.0145))
        p.addLine(to: P(0.3842, 0.0135))
        p.addLine(to: P(0.3882, 0.0126))
        p.addLine(to: P(0.3919, 0.0118))
        p.addLine(to: P(0.3960, 0.0109))
        p.addLine(to: P(0.3998, 0.0101))
        p.addLine(to: P(0.4037, 0.0093))
        p.addLine(to: P(0.4076, 0.0086))
        p.addLine(to: P(0.4118, 0.0078))
        p.addLine(to: P(0.4155, 0.0072))
        p.addLine(to: P(0.4196, 0.0065))
        p.addLine(to: P(0.4235, 0.0059))
        p.addLine(to: P(0.4275, 0.0052))
        p.addLine(to: P(0.4313, 0.0047))
        p.addLine(to: P(0.4356, 0.0042))
        p.addLine(to: P(0.4394, 0.0037))
        p.addLine(to: P(0.4438, 0.0032))
        p.addLine(to: P(0.4475, 0.0027))
        p.addLine(to: P(0.4519, 0.0023))
        p.addCurve(to: P(0.4635, 0.0013), control1: P(0.4558, 0.0019), control2: P(0.4596, 0.0016))
        p.addLine(to: P(0.4680, 0.0010))
        p.addLine(to: P(0.4717, 0.0008))
        p.addLine(to: P(0.4763, 0.0005))
        p.addLine(to: P(0.4802, 0.0004))
        p.addLine(to: P(0.4843, 0.0002))
        p.addLine(to: P(0.4884, 0.0001))
        p.addLine(to: P(0.4925, 0.0000))
        p.addLine(to: P(0.5007, -0.0000))
        p.closeSubpath()
        return p
    }()

    static let opencode: SwiftUI.Path = {
        var p = SwiftUI.Path()
        p.move(to: P(0.6667, 0.2500))
        p.addLine(to: P(0.3333, 0.2500))
        p.addLine(to: P(0.3333, 0.7500))
        p.addLine(to: P(0.6667, 0.7500))
        p.addLine(to: P(0.6667, 0.2500))
        p.closeSubpath()
        p.move(to: P(0.8333, 0.9167))
        p.addLine(to: P(0.1667, 0.9167))
        p.addLine(to: P(0.1667, 0.0833))
        p.addLine(to: P(0.8333, 0.0833))
        p.addLine(to: P(0.8333, 0.9167))
        p.closeSubpath()
        return p
    }()

    static let all: [String: SwiftUI.Path] = [
        "gemini": gemini, "cursor": cursor, "qwen": qwen,
        "kimi": kimi, "opencode": opencode,
    ]
}

/// Scales a unit-space brand path into the target rect.
struct BrandMarkShape: Shape {
    let unit: SwiftUI.Path
    func path(in rect: CGRect) -> SwiftUI.Path {
        unit.applying(CGAffineTransform(a: rect.width, b: 0, c: 0, d: rect.height,
                                        tx: rect.minX, ty: rect.minY))
    }
}

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
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if source == "codex" {
            OpenAILogoShape()
                .fill(Color(hex: 0xE8E8E3))
                .frame(width: size, height: size)
        } else if let unit = BrandPaths.all[source] {
            BrandMarkShape(unit: unit)
                .fill(VNColor.agent(source))
                .frame(width: size, height: size)
        } else if let sprite = agentSprites[source] {
            let cols = CGFloat(sprite.frameA[0].count)
            let rows = CGFloat(sprite.frameA.count)
            let px = size / cols
            TimelineView(.periodic(from: .now, by: 0.45)) { ctx in
                let useA = !animated || reduceMotion || sprite.frameB == nil
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


/// Compact activity glyph: three pixel bars that dance while agents work,
/// still and dim when everything is idle.
struct PixelSpinner: View {
    var active: Bool
    var color: Color = Color(hex: 0x6FB982)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let frames: [[CGFloat]] = [
        [3, 6, 4], [5, 3, 6], [6, 5, 3], [4, 6, 5],
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.28)) { ctx in
            let heights: [CGFloat] = (active && !reduceMotion)
                ? Self.frames[Int(ctx.date.timeIntervalSinceReferenceDate / 0.28) % Self.frames.count]
                : [3, 4, 3]
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<3, id: \.self) { i in
                    Rectangle()
                        .fill(color.opacity(active ? 0.95 : 0.35))
                        .frame(width: 2, height: heights[i])
                }
            }
            .frame(height: 7, alignment: .bottom)
        }
    }
}
