import Foundation
import VibeNotchCore

// vibenotch-hook: the client wired into agent configs. FAIL-OPEN ALWAYS — if the app
// is down or anything errors, exit 0 with no decision so the agent proceeds normally.

func argValue(after flag: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
    return a[i + 1]
}

/// Pick the most human-relevant field from a tool input for the card subtitle.
func summarize(_ input: [String: Any]?) -> String? {
    guard let input else { return nil }
    for key in ["command", "file_path", "path", "url", "pattern"] {
        if let v = input[key] as? String { return v }
    }
    if let data = try? JSONSerialization.data(withJSONObject: input),
       let s = String(data: data, encoding: .utf8) { return s }
    return nil
}

/// Text of the last assistant message in a Claude Code transcript (JSONL).
/// ponytail: reads the whole file; for very long sessions, tail-read the last chunk.
func lastAssistantText(_ path: String?) -> String? {
    guard let path, let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    for line in content.split(separator: "\n").reversed() {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
        let msg = (obj["message"] as? [String: Any]) ?? obj
        let role = (msg["role"] as? String) ?? (obj["type"] as? String)
        guard role == "assistant" else { continue }
        if let text = extractText(msg["content"]) ?? extractText(obj["content"]), !text.isEmpty {
            return text
        }
    }
    return nil
}

private func extractText(_ content: Any?) -> String? {
    if let s = content as? String { return s }
    if let parts = content as? [[String: Any]] {
        let texts = parts.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }
    return nil
}

/// Display name of the terminal the agent runs in, from inherited env.
func terminalName() -> String? {
    let env = ProcessInfo.processInfo.environment
    if env["GHOSTTY_RESOURCES_DIR"] != nil || env["GHOSTTY_BIN_DIR"] != nil { return "Ghostty" }
    guard let t = env["TERM_PROGRAM"], !t.isEmpty else { return nil }
    switch t {
    case "iTerm.app": return "iTerm"
    case "Apple_Terminal": return "Terminal"
    case "vscode": return "VS Code"
    case "WarpTerminal": return "Warp"
    default: return t.lowercased().contains("ghostty") ? "Ghostty" : t
    }
}

let source = argValue(after: "--source") ?? "claude"
let terminal = terminalName()

if source == "codex" {
    // Codex `notify`: the JSON payload is the last CLI argument.
    let payload = CommandLine.arguments.last.flatMap { $0.data(using: .utf8) } ?? Data()
    let obj = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
    let msg = VNInbound(
        type: .notify, source: "codex",
        event: (obj?["type"] as? String) ?? "agent-turn-complete",
        title: "Codex is waiting",
        detail: obj?["last-assistant-message"] as? String,
        cwd: obj?["cwd"] as? String, terminal: terminal
    )
    _ = IPCClient.send(msg)
    exit(0)
}

// Claude Code: hook JSON on stdin.
let stdin = FileHandle.standardInput.readDataToEndOfFile()
let obj = (try? JSONSerialization.jsonObject(with: stdin)) as? [String: Any] ?? [:]
let event = obj["hook_event_name"] as? String ?? "Unknown"
let tool = obj["tool_name"] as? String
let toolInput = obj["tool_input"] as? [String: Any]
let cwd = obj["cwd"] as? String
let sessionId = obj["session_id"] as? String

if event == "PermissionRequest" {
    let msg = VNInbound(type: .request, source: "claude", event: event,
                        tool: tool, detail: summarize(toolInput),
                        cwd: cwd, terminal: terminal, sessionId: sessionId)
    switch IPCClient.send(msg) {
    case .allow:
        print(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#)
    case .deny:
        print(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}"#)
    case .ask, .none:
        break // no output → defer to Claude's own permission flow (fail-open)
    }
    exit(0)
}

// Only Stop and Notification become cards; other events (SessionStart, PostToolUse…)
// are dropped to keep the notch quiet.
let assistant = lastAssistantText(obj["transcript_path"] as? String)
let title: String
let detail: String?
switch event {
case "Stop":
    title = "Claude finished"
    detail = assistant
case "Notification":
    title = (obj["message"] as? String) ?? "Claude"
    detail = assistant ?? (obj["message"] as? String)
default:
    exit(0)
}
let msg = VNInbound(type: .notify, source: "claude", event: event,
                    title: title, tool: tool, detail: detail, cwd: cwd, terminal: terminal, sessionId: sessionId)
_ = IPCClient.send(msg)
exit(0)
