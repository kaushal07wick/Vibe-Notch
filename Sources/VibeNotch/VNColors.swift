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

    static func agent(_ source: String) -> Color { source == "codex" ? codex : claude }
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
