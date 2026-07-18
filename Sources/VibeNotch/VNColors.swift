import SwiftUI

/// Palette matched to Open Island's spec — warm paper on near-black ink,
/// tinted status/agent colors.
enum VNColor {
    static let paper = Color(hex: 0xF1EAD9)          // primary text
    static let ink = Color(hex: 0x0D0D0F)            // panel ground
    static let ink2 = Color.white.opacity(0.06)      // badge / chip fill
    static let hair = Color.white.opacity(0.06)      // hairlines / borders

    static let text = paper
    static let muted = paper.opacity(0.52)
    static let faint = paper.opacity(0.35)

    // status
    static let go = Color(hex: 0x6FB982)             // completed
    static let running = Color(hex: 0x6EA7FF)        // running
    static let amber = Color(hex: 0xE7A762)          // waiting
    static let stop = Color(hex: 0xF4A4A4)           // deny / approval

    static let invader = Color(hex: 0x4F7DF0)        // mascot blue

    /// Per-agent brand hue (matches Open Island's AgentSession colors).
    static func agent(_ source: String) -> Color {
        switch source {
        case "codex":    return Color(hex: 0x4AA3DF)
        case "cursor":   return Color(hex: 0x7A5CFF)
        case "gemini":   return Color(hex: 0x42E86B)
        case "grok":     return Color(hex: 0x22C55E)
        case "kimi":     return Color(hex: 0xFDE047)
        case "opencode": return Color(hex: 0xFFB547)
        default:         return Color(hex: 0xD97742) // claude
        }
    }
}

/// DepartureMono — kept for the terminal/command blocks (retro, readable code).
enum VNFont {
    static func mono(_ size: CGFloat) -> Font { .custom("Departure Mono", size: size) }
    /// SF Mono — for small badges/counts/time (matches Open Island's `.monospaced`).
    static func sysMono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Display name for an agent source.
func agentName(_ source: String) -> String {
    switch source {
    case "codex": return "codex"
    case "gemini": return "gemini"
    case "cursor": return "cursor"
    case "grok": return "grok"
    case "kimi": return "kimi"
    case "opencode": return "opencode"
    default: return "claude"
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: 1)
    }
}
