import SwiftUI

/// The locked palette from the design lab. Agent hue encodes *who* is asking.
enum VNColor {
    static let void = Color.black
    static let ink2 = Color(hex: 0x141417)
    static let hair = Color.white.opacity(0.09)
    static let text = Color(hex: 0xF2F2F0)
    static let muted = Color(hex: 0x8A8A86)
    static let faint = Color(hex: 0x57575A)

    static let go = Color(hex: 0x43C06D)
    static let stop = Color(hex: 0xE5484D)
    static let amber = Color(hex: 0xE0A34E)

    static let claude = Color(hex: 0xD97757)
    static let codex = Color(hex: 0x10A37F)
    static let invader = Color(hex: 0x4F7DF0)   // the pixel mascot blue

    /// Per-agent accent — each coding agent gets its own hue.
    static func agent(_ source: String) -> Color {
        switch source {
        case "codex":  return codex
        case "gemini": return Color(hex: 0x4285F4)  // google blue
        case "cursor": return Color(hex: 0x9AA0A6)  // graphite
        case "grok":   return Color(hex: 0x22C55E)  // green
        case "kimi":   return Color(hex: 0x7C5CFF)  // violet
        case "opencode": return Color(hex: 0xE0A34E)
        default:       return claude
        }
    }
}

/// Display name for an agent source.
func agentName(_ source: String) -> String {
    switch source {
    case "codex": return "Codex"
    case "gemini": return "Gemini"
    case "cursor": return "Cursor"
    case "grok": return "Grok"
    case "kimi": return "Kimi"
    case "opencode": return "opencode"
    default: return "Claude"
    }
}

/// DepartureMono — the pixel/terminal face that carries the retro character.
/// Bundled in Resources/Fonts and registered via Info.plist ATSApplicationFontsPath.
enum VNFont {
    static func mono(_ size: CGFloat) -> Font { .custom("Departure Mono", size: size) }
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
