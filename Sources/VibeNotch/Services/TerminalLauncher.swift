import AppKit

/// Runs a shell command in a fresh terminal tab: Ghostty when it's installed (new tab in
/// the front window), else Terminal.app. The command is typed into the user's own shell,
/// so the tab stays open afterwards.
@MainActor
enum TerminalLauncher {
    @discardableResult
    static func run(_ command: String, purpose: String) -> Bool {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") != nil {
            return VNAppleScript.run("""
            tell application "Ghostty"
                activate
                set cfg to new surface configuration
                set initial input of cfg to "\(escaped)" & linefeed
                if (count of windows) > 0 then
                    new tab in front window with configuration cfg
                else
                    new window with configuration cfg
                end if
            end tell
            return "ok"
            """, purpose: purpose + " in Ghostty") == "ok"
        }
        return VNAppleScript.run("""
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        return "ok"
        """, purpose: purpose + " in Terminal") == "ok"
    }
}
