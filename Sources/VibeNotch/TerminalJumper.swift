import AppKit

/// Focuses the terminal an agent runs in. With a tty, selects the **exact
/// tab/session** in iTerm2 or Terminal.app via AppleScript; otherwise (or for
/// terminals without a scripting API, e.g. Ghostty) activates the app.
enum TerminalJumper {
    static func jump(terminal: String?, tty: String? = nil) {
        if let tty, let terminal, jumpToTab(terminal: terminal, tty: tty) { return }
        activate(terminal)
    }

    /// Back-compat convenience.
    static func jump(_ terminal: String?) { jump(terminal: terminal, tty: nil) }

    // MARK: Exact tab via AppleScript

    private static func jumpToTab(terminal: String, tty: String) -> Bool {
        let device = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
        let script: String
        switch terminal {
        case "iTerm":
            script = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(device)" then
                                select w
                                tell w to select t
                                tell t to select s
                                activate
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return "miss"
            """
        case "Terminal":
            script = """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(device)" then
                            set selected of t to true
                            set index of w to 1
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end tell
            return "miss"
            """
        default:
            return false
        }
        return runAppleScript(script) == "ok"
    }

    private static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("VibeNotch: jump script error: \(error)"); return nil }
        return result?.stringValue
    }

    // MARK: App activation fallback

    private static func activate(_ terminal: String?) {
        guard let bundleID = bundleID(for: terminal),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
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
