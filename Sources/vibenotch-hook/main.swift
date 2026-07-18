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

let source = argValue(after: "--source") ?? "claude"

if source == "codex" {
    // Codex `notify`: the JSON payload is the last CLI argument.
    let payload = CommandLine.arguments.last.flatMap { $0.data(using: .utf8) } ?? Data()
    let obj = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
    let msg = VNInbound(
        type: .notify, source: "codex",
        event: (obj?["type"] as? String) ?? "agent-turn-complete",
        detail: obj?["last-assistant-message"] as? String,
        cwd: obj?["cwd"] as? String
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
                        cwd: cwd, sessionId: sessionId)
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

// Every other event is a fire-and-forget notification.
let msg = VNInbound(type: .notify, source: "claude", event: event,
                    tool: tool, detail: summarize(toolInput), cwd: cwd, sessionId: sessionId)
_ = IPCClient.send(msg)
exit(0)
