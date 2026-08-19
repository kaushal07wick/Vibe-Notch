import AppKit
import VibeNotchCore

/// Focuses the terminal an agent runs in. With a tty, selects the **exact
/// tab/session** in iTerm2 or Terminal.app via AppleScript; otherwise (or for
/// terminals without a scripting API, e.g. Ghostty) activates the app.
enum TerminalJumper {
    static func jump(terminal: String?, tty: String? = nil, meta: [String: String] = [:]) {
        let plan = JumpPlan.make(terminal: terminal, tty: tty, meta: meta)
        if let command = plan.command { runCommand(command) } // pane focus (tmux/wezterm/kitty)
        if plan.useTTYScript, let terminal, let tty, jumpToTab(terminal: terminal, tty: tty) { return }
        activate(bundleID: plan.bundleID, name: terminal)
    }

    /// Back-compat convenience.
    static func jump(_ terminal: String?) { jump(terminal: terminal, tty: nil) }

    /// Best-effort CLI focus (tmux switch-client / wezterm activate-pane / kitty focus).
    private static func runCommand(_ argv: [String]) {
        guard let exe = argv.first else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = Array(argv.dropFirst())
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

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
        return VNAppleScript.run(script, purpose: "jumping to the \(terminal) tab") == "ok"
    }

    // MARK: App activation fallback

    private static func activate(bundleID: String?, name: String?) {
        if let bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
            return
        }
        // Unknown terminal — try activating a running app by name. Match both
        // directions: TERM_PROGRAM is often longer than the app's name
        // ("waveterm" vs "Wave"), and a one-way contains missed every one.
        if let name, let app = NSWorkspace.shared.runningApplications.first(where: {
            guard let appName = $0.localizedName else { return false }
            return appName.localizedCaseInsensitiveContains(name)
                || (appName.count >= 3 && name.localizedCaseInsensitiveContains(appName))
        }) {
            app.activate()
        }
    }
}
