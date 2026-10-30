import AppKit
import VibeNotchCore

/// Acts on a session's terminal: type a reply into the exact pane, or
/// interrupt (^C) the foreground process. Local sessions only.
@MainActor
enum TerminalControl {
    private static var sending: Set<String> = []
    static func hasExactTarget(_ s: SessionActivity) -> Bool {
        s.host == nil && InjectionPlan.make(terminal: s.terminal, tty: s.tty,
                                            meta: s.termMeta ?? [:], text: "x").isSupported
    }

    static func canReply(to s: SessionActivity) -> Bool {
        s.host == nil && (hasExactTarget(s) || JumpPlan.make(terminal: s.terminal,
            tty: s.tty, meta: s.termMeta ?? [:]).bundleID != nil)
    }

    /// Completion means the terminal accepted the input, not that the agent finished it.
    static func send(_ text: String, to s: SessionActivity, allowActiveTab: Bool = false) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0"), s.host == nil else { return false }
        guard sending.insert(s.id).inserted else { return false }
        defer { sending.remove(s.id) }
        let plan = InjectionPlan.make(terminal: s.terminal, tty: s.tty,
                                      meta: s.termMeta ?? [:], text: trimmed)
        if plan.isSupported {
            if !plan.commands.isEmpty, !(await TerminalCommand.run(plan.commands)) { return false }
            if let script = plan.appleScript,
               VNAppleScript.run(script, purpose: "sending to the session") != "ok" { return false }
        } else {
            // ponytail: app-only terminals cannot identify a pane. Require an explicit
            // active-tab choice; add their pane APIs when available.
            guard allowActiveTab, await sendByTyping(trimmed, to: s) else { return false }
        }
        StatsLog.bump("replies")
        return true
    }

    private static func sendByTyping(_ text: String, to s: SessionActivity) async -> Bool {
        let plan = JumpPlan.make(terminal: s.terminal, tty: s.tty, meta: s.termMeta ?? [:])
        guard let bundleID = plan.bundleID,
              await TerminalJumper.focus(terminal: s.terminal, tty: s.tty, meta: s.termMeta ?? [:]) else { return false }
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else { return false }
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        return VNAppleScript.run("""
            tell application "System Events"
                if bundle identifier of first application process whose frontmost is true is not "\(bundleID)" then return "miss"
                keystroke "\(escaped)"
                key code 36
            end tell
            return "ok"
            """, purpose: "typing into the active terminal tab") == "ok"
    }

    static func switchModel(_ model: String, in s: SessionActivity, allowActiveTab: Bool = false) async -> Bool {
        guard ["claude", "codex"].contains(s.source),
              !model.contains(where: { $0.isNewline || $0.asciiValue == 0 }) else { return false }
        let name = model.trimmingCharacters(in: .whitespaces)
        return await send(name.isEmpty ? "/model" : "/model \(name)", to: s, allowActiveTab: allowActiveTab)
    }

    /// Stops the agent's current turn without exiting it: sends Esc (what Claude and
    /// Codex treat as "interrupt"). A SIGINT would kill the CLI, and macOS refuses
    /// TIOCSTI, so tmux gets send-keys and everything else gets Esc typed into the
    /// session's focused terminal tab.
    @discardableResult
    static func interrupt(_ s: SessionActivity) async -> Bool {
        guard await press(tmux: "Escape", keyCode: 53, in: s, purpose: "interrupting the agent") else { return false }
        StatsLog.bump("interrupts")
        return true
    }

    /// One special key into the session: tmux send-keys when it lives in tmux, otherwise
    /// focus its terminal tab and press the key there.
    static func press(tmux key: String, keyCode: Int, shift: Bool = false, in s: SessionActivity, purpose: String) async -> Bool {
        guard s.host == nil else { return false }
        let meta = s.termMeta ?? [:]
        if let pane = meta["TMUX_PANE"], let tmux = meta["TMUX"] {
            let socket = tmux.split(separator: ",").first.map(String.init) ?? ""
            return await TerminalCommand.run([["/usr/bin/env", "tmux", "-S", socket, "send-keys", "-t", pane, key]])
        }
        let plan = JumpPlan.make(terminal: s.terminal, tty: s.tty, meta: meta)
        guard let bundleID = plan.bundleID,
              await TerminalJumper.focus(terminal: s.terminal, tty: s.tty, meta: meta) else { return false }
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return VNAppleScript.run("""
            tell application "System Events"
                if bundle identifier of first application process whose frontmost is true is not "\(bundleID)" then return "miss"
                key code \(keyCode)\(shift ? " using shift down" : "")
            end tell
            return "ok"
            """, purpose: purpose) == "ok"
    }

    // MARK: helpers

    private static func output(_ exe: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
