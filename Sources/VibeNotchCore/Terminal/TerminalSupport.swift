import Foundation

/// Identifies which terminal an agent runs in and captures the metadata needed
/// to jump back to the exact pane/tab later. Pure functions — fully testable.
public enum TerminalDetector {
    /// Env keys worth carrying for precise jumps.
    static let metaKeys = [
        "WEZTERM_PANE", "TMUX", "TMUX_PANE",
        "KITTY_WINDOW_ID", "KITTY_LISTEN_ON", "ITERM_SESSION_ID",
    ]

    /// Terminal display name from the process environment.
    public static func detect(env: [String: String]) -> (name: String?, meta: [String: String]) {
        var meta: [String: String] = [:]
        for key in metaKeys where env[key] != nil { meta[key] = env[key] }

        let name: String?
        if env["GHOSTTY_RESOURCES_DIR"] != nil || env["GHOSTTY_BIN_DIR"] != nil {
            name = "Ghostty"
        } else if env["WEZTERM_PANE"] != nil || env["TERM_PROGRAM"] == "WezTerm" {
            name = "WezTerm"
        } else if env["KITTY_WINDOW_ID"] != nil {
            name = "kitty"
        } else if env["ALACRITTY_WINDOW_ID"] != nil || env["ALACRITTY_SOCKET"] != nil {
            name = "Alacritty"
        } else if env["ZELLIJ"] != nil {
            name = "Zellij"
        } else if env["TERMINAL_EMULATOR"]?.contains("JetBrains") == true {
            name = "JetBrains"
        } else if let program = env["TERM_PROGRAM"], !program.isEmpty {
            name = displayName(forTermProgram: program, env: env)
        } else {
            name = nil
        }
        return (name, meta)
    }

    static func displayName(forTermProgram program: String, env: [String: String]) -> String {
        switch program {
        case "iTerm.app": return "iTerm"
        case "Apple_Terminal": return "Terminal"
        case "WarpTerminal": return "Warp"
        case "WezTerm": return "WezTerm"
        case "Hyper": return "Hyper"
        case "Tabby": return "Tabby"
        case "rio": return "Rio"
        case "zed": return "Zed"
        case "vscode":
            // VS Code forks share TERM_PROGRAM=vscode; tell them apart by paths.
            let hints = [env["VSCODE_GIT_ASKPASS_MAIN"], env["VSCODE_GIT_ASKPASS_NODE"], env["__CFBundleIdentifier"]]
                .compactMap { $0 }.joined(separator: " ")
            if hints.localizedCaseInsensitiveContains("cursor") { return "Cursor" }
            if hints.localizedCaseInsensitiveContains("windsurf") { return "Windsurf" }
            if hints.localizedCaseInsensitiveContains("antigravity") { return "Antigravity" }
            return "VS Code"
        default:
            return program.lowercased().contains("ghostty") ? "Ghostty" : program
        }
    }

    /// Fallback when the env says nothing: match an ancestor process name.
    public static func nameFromProcessList(_ ancestors: [String]) -> String? {
        let known: [(pattern: String, name: String)] = [
            ("iTerm", "iTerm"), ("wezterm", "WezTerm"), ("kitty", "kitty"),
            ("alacritty", "Alacritty"), ("ghostty", "Ghostty"),
            ("Terminal", "Terminal"), ("Warp", "Warp"), ("Hyper", "Hyper"),
            ("tabby", "Tabby"), ("rio", "Rio"), ("zed", "Zed"),
            ("Cursor", "Cursor"), ("Windsurf", "Windsurf"), ("Electron", "VS Code"),
        ]
        for ancestor in ancestors {
            if let match = known.first(where: { ancestor.localizedCaseInsensitiveContains($0.pattern) }) {
                return match.name
            }
        }
        return nil
    }
}

/// How to focus a session's exact pane: a precise command (best effort) plus
/// the app to activate. Pure so strategy selection is testable; the app runs it.
public struct JumpPlan: Equatable, Sendable {
    /// argv to run before activating (e.g. tmux/wezterm CLI focus), if any.
    public var command: [String]?
    /// AppleScript tty tab selection applies (iTerm/Terminal only).
    public var useTTYScript: Bool
    public var bundleID: String?

    public static func make(terminal: String?, tty: String?, meta: [String: String]) -> JumpPlan {
        var plan = JumpPlan(command: nil, useTTYScript: false, bundleID: bundleID(for: terminal))

        // Multiplexer first: focusing the tmux pane also needs the host app up.
        if let pane = meta["TMUX_PANE"], let tmux = meta["TMUX"] {
            // $TMUX = "<socket>,<pid>,<session>"
            let socket = tmux.split(separator: ",").first.map(String.init) ?? ""
            plan.command = ["/usr/bin/env", "tmux", "-S", socket, "switch-client", "-t", pane]
            return plan
        }
        if let pane = meta["WEZTERM_PANE"] {
            plan.command = ["/usr/bin/env", "wezterm", "cli", "activate-pane", "--pane-id", pane]
            return plan
        }
        if let window = meta["KITTY_WINDOW_ID"], let listen = meta["KITTY_LISTEN_ON"] {
            plan.command = ["/usr/bin/env", "kitty", "@", "--to", listen,
                            "focus-window", "--match", "id:\(window)"]
            return plan
        }
        if tty != nil, terminal == "iTerm" || terminal == "Terminal" {
            plan.useTTYScript = true
        }
        return plan
    }

    static func bundleID(for terminal: String?) -> String? {
        switch terminal {
        case "Ghostty": return "com.mitchellh.ghostty"
        case "iTerm": return "com.googlecode.iterm2"
        case "Terminal": return "com.apple.Terminal"
        case "Warp": return "dev.warp.Warp-Stable"
        case "WezTerm": return "com.github.wez.wezterm"
        case "kitty": return "net.kovidgoyal.kitty"
        case "Alacritty": return "org.alacritty"
        case "Hyper": return "co.zeit.hyper"
        case "Tabby": return "org.tabby"
        case "Rio": return "com.raphaelamorim.rio"
        case "Zed": return "dev.zed.Zed"
        case "VS Code": return "com.microsoft.VSCode"
        case "Cursor": return "com.todesktop.230313mzl4w4u92"
        case "Windsurf": return "com.exafunction.windsurf"
        default: return nil
        }
    }
}

/// How to type text into a session's exact terminal (reply-from-notch).
/// Pure strategy; the app executes. `nil` command + `nil` script = unsupported.
public struct InjectionPlan: Equatable, Sendable {
    public var commands: [[String]] = []     // CLI steps (tmux/wezterm/kitty)
    public var appleScript: String?          // iTerm / Terminal.app path

    public var isSupported: Bool { !commands.isEmpty || appleScript != nil }

    public static func make(terminal: String?, tty: String?,
                            meta: [String: String], text: String) -> InjectionPlan {
        var plan = InjectionPlan()
        if let pane = meta["TMUX_PANE"], let tmux = meta["TMUX"] {
            let socket = tmux.split(separator: ",").first.map(String.init) ?? ""
            plan.commands = [
                ["/usr/bin/env", "tmux", "-S", socket, "send-keys", "-t", pane, "-l", text],
                ["/usr/bin/env", "tmux", "-S", socket, "send-keys", "-t", pane, "Enter"],
            ]
            return plan
        }
        if let pane = meta["WEZTERM_PANE"] {
            plan.commands = [["/usr/bin/env", "wezterm", "cli", "send-text",
                              "--pane-id", pane, "--no-paste", text + "\r"]]
            return plan
        }
        if let window = meta["KITTY_WINDOW_ID"], let listen = meta["KITTY_LISTEN_ON"] {
            plan.commands = [["/usr/bin/env", "kitty", "@", "--to", listen, "send-text",
                              "--match", "id:\(window)", text + "\r"]]
            return plan
        }
        guard let tty else { return plan }
        let device = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        switch terminal {
        case "iTerm":
            plan.appleScript = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(device)" then
                                tell s to write text "\(escaped)"
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        case "Terminal":
            plan.appleScript = """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(device)" then
                            do script "\(escaped)" in t
                            return "ok"
                        end if
                    end repeat
                end repeat
            end tell
            """
        default:
            break
        }
        return plan
    }
}

/// Panic-button support: parse `ps -t <tty> -o tpgid=` output into the
/// foreground process group to SIGINT.
public enum ProcessGroup {
    public static func foregroundPGID(fromPS output: String) -> Int32? {
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let pgid = Int32(trimmed), pgid > 1 { return pgid }
        }
        return nil
    }
}
