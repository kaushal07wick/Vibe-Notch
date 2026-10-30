import AppKit
import VibeNotchCore

/// Focuses the terminal an agent runs in. With a tty, selects the **exact
/// tab/session** in iTerm2 or Terminal.app via AppleScript; otherwise (or for
/// terminals without a scripting API, e.g. Ghostty) activates the app.
@MainActor
enum TerminalJumper {
    static func jump(terminal: String?, tty: String? = nil, meta: [String: String] = [:]) {
        Task {
            if !(await focus(terminal: terminal, tty: tty, meta: meta)) {
                let alert = NSAlert()
                alert.messageText = "Couldn’t reach the terminal"
                alert.informativeText = "Check that this session’s terminal is open and that Vibe Notch has Automation permission."
                alert.runModal()
            }
        }
    }

    static func focus(terminal: String?, tty: String? = nil, meta: [String: String] = [:]) async -> Bool {
        let plan = JumpPlan.make(terminal: terminal, tty: tty, meta: meta)
        if let command = plan.command, !(await TerminalCommand.run([command])) { return false }
        if plan.useTTYScript, let terminal, let tty { return jumpToTab(terminal: terminal, tty: tty) }
        return await activate(bundleID: plan.bundleID, name: terminal)
    }

    static func jump(_ terminal: String?) { jump(terminal: terminal) }

    // MARK: Exact tab via AppleScript

    private static func jumpToTab(terminal: String, tty: String) -> Bool {
        guard TerminalCommand.validTTY(tty) else { return false }
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
        return VNAppleScript.run(script, purpose: "jumping to the \(terminal) tab") == "ok"
    }

    // MARK: App activation fallback

    private static func activate(bundleID: String?, name: String?) async -> Bool {
        if let bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            do { _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config); return true }
            catch { return false }
        }
        // Unknown terminal — try activating a running app by name. Match both
        // directions: TERM_PROGRAM is often longer than the app's name
        // ("waveterm" vs "Wave"), and a one-way contains missed every one.
        if let name, let app = NSWorkspace.shared.runningApplications.first(where: {
            guard let appName = $0.localizedName else { return false }
            return appName.localizedCaseInsensitiveContains(name)
                || (appName.count >= 3 && name.localizedCaseInsensitiveContains(appName))
        }) {
            return app.activate()
        }
        return false
    }
}
