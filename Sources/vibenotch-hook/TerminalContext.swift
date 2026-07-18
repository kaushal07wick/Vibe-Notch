import Foundation
import VibeNotchCore

// Which terminal/tty is this agent in?

/// The controlling terminal (e.g. "ttys014") — walk up the process tree until
/// a process with a tty is found. Enables exact-tab jump.
func ttyName() -> String? {
    var pid = getppid()
    for _ in 0..<6 {
        guard pid > 1 else { break }
        let out = shell("/bin/ps", ["-p", "\(pid)", "-o", "tty=,ppid="])
        guard let out else { break }
        let parts = out.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { break }
        if parts[0] != "??" { return parts[0] }
        pid = Int32(parts[1]) ?? 1
    }
    return nil
}

func shell(_ path: String, _ args: [String]) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Terminal identity + precise-jump metadata. Env first; if the env says
/// nothing (some agents scrub it), fall back to ancestor process names.
func detectTerminal() -> (name: String?, meta: [String: String]) {
    let detected = TerminalDetector.detect(env: ProcessInfo.processInfo.environment)
    if detected.name != nil { return detected }
    var ancestors: [String] = []
    var pid = getppid()
    for _ in 0..<8 {
        guard pid > 1, let out = shell("/bin/ps", ["-p", "\(pid)", "-o", "comm=,ppid="]) else { break }
        let parts = out.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { break }
        ancestors.append(parts.dropLast().joined(separator: " "))
        pid = Int32(parts.last ?? "") ?? 1
    }
    return (TerminalDetector.nameFromProcessList(ancestors), detected.meta)
}
