import AppKit

/// Focuses the terminal an agent runs in. v1 activates the app; precise
/// window/tab targeting (OSC-2 titles / Ghostty bindings) is a later phase.
enum TerminalJumper {
    static func jump(_ terminal: String?) {
        guard let bundleID = bundleID(for: terminal),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            if let name = terminal { NSWorkspace.shared.launchApplication(name) }
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    private static func bundleID(for terminal: String?) -> String? {
        switch terminal {
        case "Ghostty": return "com.mitchellh.ghostty"
        case "iTerm": return "com.googlecode.iterm2"
        case "Terminal": return "com.apple.Terminal"
        case "VS Code": return "com.microsoft.VSCode"
        case "Warp": return "dev.warp.Warp-Stable"
        default: return nil
        }
    }
}
