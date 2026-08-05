import AppKit
import VibeNotchCore

/// User-rebindable keyboard shortcuts.
///
/// Matching prefers the typed character over the physical key code, so a
/// binding recorded as ⌃A stays ⌃A on AZERTY and Dvorak instead of drifting to
/// whatever letter sits where QWERTY's A is. Key code is the fallback for keys
/// that produce no character (esc, arrows, F-keys).
struct VNShortcut: Codable, Equatable {
    var keyCode: UInt16
    /// `charactersIgnoringModifiers`, lowercased. Empty for non-printing keys.
    var characters: String
    /// `NSEvent.ModifierFlags` raw value, already normalized.
    var modifiers: UInt

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    init(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.characters = characters.lowercased()
        self.modifiers = modifiers.intersection(Self.relevantModifiers).rawValue
    }

    init?(event: NSEvent) {
        let mods = event.modifierFlags.intersection(Self.relevantModifiers)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        // A bare printing key would swallow normal typing — require a modifier
        // unless it's a key that can't be typed into text anyway.
        let standalone: Set<UInt16> = [53, 36, 48, 49] // esc, return, tab, space
        guard !mods.isEmpty || standalone.contains(event.keyCode) else { return nil }
        self.init(keyCode: event.keyCode, characters: chars, modifiers: mods)
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    func matches(_ event: NSEvent) -> Bool {
        KeyBindingRules.matches(
            storedCharacters: characters, storedKeyCode: keyCode, storedModifiers: modifiers,
            eventCharacters: event.charactersIgnoringModifiers ?? "",
            eventKeyCode: event.keyCode,
            eventModifiers: event.modifierFlags.rawValue)
    }

    /// "⌃A", "esc" — what the Settings row shows.
    var display: String {
        KeyBindingRules.display(keyCode: keyCode, characters: characters, modifiers: modifiers)
    }
}

/// Everything a shortcut can trigger. Each case is backed by real behavior —
/// deny / always-allow / bypass had no key at all before this.
enum VNAction: String, CaseIterable, Identifiable {
    case approve, deny, alwaysAllow, bypass, jump, collapse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .approve: "Approve"
        case .deny: "Deny"
        case .alwaysAllow: "Always Allow"
        case .bypass: "Bypass permissions"
        case .jump: "Jump to terminal"
        case .collapse: "Collapse panel"
        }
    }

    var caption: String {
        switch self {
        case .approve: "Allow the front permission card."
        case .deny: "Refuse it — the agent is told no."
        case .alwaysAllow: "Allow and persist a rule for this tool."
        case .bypass: "Allow, then auto-approve the rest of this session."
        case .jump: "Focus the exact tab or pane the agent is in."
        case .collapse: "Active only while the panel is expanded."
        }
    }

    var defaultShortcut: VNShortcut {
        switch self {
        case .approve: .init(keyCode: 0, characters: "a", modifiers: .control)
        case .deny: .init(keyCode: 45, characters: "n", modifiers: .control)
        case .alwaysAllow: .init(keyCode: 37, characters: "l", modifiers: .control)
        case .bypass: .init(keyCode: 11, characters: "b", modifiers: .control)
        case .jump: .init(keyCode: 5, characters: "g", modifiers: .control)
        case .collapse: .init(keyCode: 53, characters: "", modifiers: [])
        }
    }
}

/// Persistence. A missing key means "default"; an explicit null means the user
/// cleared it, which is different and must survive a relaunch.
@MainActor
enum VNShortcuts {
    private static let d = UserDefaults.standard
    private static func key(_ action: VNAction) -> String { "shortcut.\(action.rawValue)" }

    static func get(_ action: VNAction) -> VNShortcut? {
        guard let data = d.data(forKey: key(action)) else { return action.defaultShortcut }
        // Empty data is the tombstone for "cleared".
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(VNShortcut.self, from: data)
    }

    static func set(_ shortcut: VNShortcut?, for action: VNAction) {
        guard let shortcut else { d.set(Data(), forKey: key(action)); return }
        d.set(try? JSONEncoder().encode(shortcut), forKey: key(action))
    }

    static func reset(_ action: VNAction) { d.removeObject(forKey: key(action)) }

    /// The action this event triggers, if any. First match wins.
    static func action(for event: NSEvent) -> VNAction? {
        VNAction.allCases.first { get($0)?.matches(event) == true }
    }

    /// Another action already using this combination — the recorder refuses
    /// duplicates rather than silently shadowing an existing binding.
    static func conflict(_ shortcut: VNShortcut, excluding action: VNAction) -> VNAction? {
        VNAction.allCases.first { $0 != action && get($0) == shortcut }
    }
}
