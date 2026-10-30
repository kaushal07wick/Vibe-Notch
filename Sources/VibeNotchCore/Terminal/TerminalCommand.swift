import Foundation

/// Bounded CLI execution, off the UI thread. Steps stop at the first failure.
public enum TerminalCommand {
    public static func run(_ commands: [[String]], timeout: TimeInterval = 5) async -> Bool {
        await Task.detached {
            for argv in commands {
                guard let executable = argv.first else { return false }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = Array(argv.dropFirst())
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = (env["PATH"] ?? "/usr/bin:/bin") + ":/opt/homebrew/bin:/usr/local/bin"
                process.environment = env
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do { try process.run() } catch { return false }
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
                if process.isRunning {
                    process.terminate()
                    // Bound even a child that ignores SIGTERM.
                    try? await Task.sleep(for: .milliseconds(50))
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    process.waitUntilExit()
                    return false
                }
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return false }
            }
            return !commands.isEmpty
        }.value
    }

    public static func resume(source: String, id: String, cwd: String) -> String? {
        guard ["claude", "codex"].contains(source), !id.isEmpty, !id.hasPrefix("-"),
              cwd.hasPrefix("/"), !id.contains("\0"), !cwd.contains("\0") else { return nil }
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = source == "codex" ? "codex resume" : "claude --resume"
        return "cd \(quote(cwd)) && \(command) \(quote(id))"
    }

    public static func validTTY(_ tty: String) -> Bool {
        let name = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
        return name.hasPrefix("tty") && name.count > 3 && name.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }
    }
}
