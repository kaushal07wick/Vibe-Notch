import Foundation
import VibeNotchCore

// Which terminal/tty is this agent in?

/// Our ancestor chain, read once from the kernel. Both the tty lookup and the
/// terminal-name fallback used to walk it with their own `ps` spawns.
private let ancestry = ProcessAncestry.walk(from: getppid(), limit: 8)

/// The controlling terminal (e.g. "ttys014") — nearest ancestor that has one.
func ttyName() -> String? {
    ancestry.prefix(6).compactMap(\.tty).first
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
    return (TerminalDetector.nameFromProcessList(ancestry.map(\.path)), detected.meta)
}
