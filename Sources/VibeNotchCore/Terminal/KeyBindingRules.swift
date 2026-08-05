import Foundation

/// The pure half of keyboard-shortcut matching, kept out of the app target so
/// it can be tested without an NSEvent.
///
/// Modifier values mirror AppKit's `NSEvent.ModifierFlags` raw values, which
/// are fixed public constants — duplicating the four we care about is cheaper
/// than dragging AppKit into Core.
public enum KeyBindingRules {
    public static let shift: UInt = 1 << 17
    public static let control: UInt = 1 << 18
    public static let option: UInt = 1 << 19
    public static let command: UInt = 1 << 20

    /// Only these four distinguish a binding — caps lock, fn, and the numeric
    /// pad flag ride along on ordinary keystrokes and would break every match.
    public static let mask: UInt = shift | control | option | command

    /// Does a stored binding fire for this key event?
    ///
    /// Character comparison wins when both sides produced one, so a binding
    /// recorded as ⌃A is still ⌃A on AZERTY rather than drifting to the letter
    /// that happens to sit at QWERTY's A position. Key code is the fallback for
    /// keys that type nothing (esc, arrows, F-keys).
    public static func matches(storedCharacters: String, storedKeyCode: UInt16, storedModifiers: UInt,
                               eventCharacters: String, eventKeyCode: UInt16, eventModifiers: UInt) -> Bool {
        guard storedModifiers & mask == eventModifiers & mask else { return false }
        if !storedCharacters.isEmpty, !eventCharacters.isEmpty {
            return storedCharacters.lowercased() == eventCharacters.lowercased()
        }
        return storedKeyCode == eventKeyCode
    }

    /// "⌃A", "⇧⌘K", "esc" — modifiers in the order macOS prints them.
    public static func display(keyCode: UInt16, characters: String, modifiers: UInt) -> String {
        var out = ""
        if modifiers & control != 0 { out += "⌃" }
        if modifiers & option != 0 { out += "⌥" }
        if modifiers & shift != 0 { out += "⇧" }
        if modifiers & command != 0 { out += "⌘" }
        return out + keyName(keyCode: keyCode, characters: characters)
    }

    public static func keyName(keyCode: UInt16, characters: String) -> String {
        switch keyCode {
        case 53: return "esc"
        case 36: return "return"
        case 48: return "tab"
        case 49: return "space"
        case 51: return "delete"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return characters.uppercased()
        }
    }
}
