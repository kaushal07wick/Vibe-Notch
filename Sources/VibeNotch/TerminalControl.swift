import AppKit
import VibeNotchCore

/// Acts on a session's terminal: type a reply into the exact pane, or
/// interrupt (^C) the foreground process. Local sessions only.
enum TerminalControl {
    /// Whether reply-from-notch can reach this session's terminal.
    static func canReply(to s: SessionActivity) -> Bool {
        s.host == nil && InjectionPlan.make(terminal: s.terminal, tty: s.tty,
                                            meta: s.termMeta ?? [:], text: "x").isSupported
    }

    /// Type `text` + Enter into the session's terminal. Returns false when the
    /// terminal has no injection path (UI should disable the reply field).
    @discardableResult
    static func send(_ text: String, to s: SessionActivity) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, s.host == nil else { return false }
        let plan = InjectionPlan.make(terminal: s.terminal, tty: s.tty,
                                      meta: s.termMeta ?? [:], text: trimmed)
        guard plan.isSupported else { return false }
        for argv in plan.commands { run(argv) }
        if let script = plan.appleScript { runAppleScript(script) }
        StatsLog.bump("replies")
        return true
    }

    /// Switch the agent's model by typing its slash command into the pane.
    /// Claude/forks take `/model <name>`; Codex's `/model` opens its own picker.
    @discardableResult
    static func switchModel(_ model: String, in s: SessionActivity) -> Bool {
        let cmd = model.isEmpty ? "/model" : "/model \(model)"
        return send(cmd, to: s)
    }

    /// Panic button: SIGINT the foreground process group on the session's tty —
    /// exactly what ^C in that terminal would do.
    @discardableResult
    static func interrupt(_ s: SessionActivity) -> Bool {
        guard s.host == nil, let tty = s.tty else { return false }
        let name = tty.replacingOccurrences(of: "/dev/", with: "")
        guard let out = output("/bin/ps", ["-t", name, "-o", "tpgid="]),
              let pgid = ProcessGroup.foregroundPGID(fromPS: out) else { return false }
        StatsLog.bump("interrupts")
        return kill(-pgid, SIGINT) == 0
    }

    // MARK: helpers

    private static func run(_ argv: [String]) {
        guard let exe = argv.first else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = Array(argv.dropFirst())
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

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
        return String(data: data, encoding: .utf8)
    }

    private static func runAppleScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("VibeNotch: injection script error: \(error)") }
    }
}
