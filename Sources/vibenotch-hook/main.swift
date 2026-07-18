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

/// The model id from the last assistant message, mapped to a friendly name.
func lastAssistantModel(_ path: String?) -> String? {
    guard let path, let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    for line in content.split(separator: "\n").reversed() {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
        let msg = (obj["message"] as? [String: Any]) ?? obj
        guard (msg["role"] as? String) == "assistant", let id = msg["model"] as? String else { continue }
        return friendlyModel(id)
    }
    return nil
}

func friendlyModel(_ id: String) -> String {
    let parts = id.lowercased().split(separator: "-").map(String.init)
    let families = ["opus": "Opus", "sonnet": "Sonnet", "haiku": "Haiku", "fable": "Fable"]
    guard let idx = parts.firstIndex(where: { families[$0] != nil }) else { return id }
    let family = families[parts[idx]]!
    let nums = parts[(idx + 1)...].prefix(while: { Int($0) != nil }).prefix(2)
    return nums.isEmpty ? family : "\(family) \(nums.joined(separator: "."))"
}

private func extractText(_ content: Any?) -> String? {
    if let s = content as? String { return s }
    if let parts = content as? [[String: Any]] {
        let texts = parts.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }
    return nil
}

/// First meaningful line of text — skips code fences, blanks, and markdown headers —
/// so the notch never shows a raw multi-line code dump. Truncated to one line.
func oneLine(_ text: String?) -> String? {
    guard let text else { return nil }
    var inFence = false
    for raw in text.components(separatedBy: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("```") { inFence.toggle(); continue }
        if inFence || line.isEmpty || line.hasPrefix("#") { continue }
        return String(line.prefix(120))
    }
    return nil
}

/// First (task) or last user message in a transcript, skipping tool-result/system noise.
func userText(_ path: String?, first: Bool) -> String? {
    guard let path, let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    let lines = content.split(separator: "\n")
    for line in (first ? Array(lines) : lines.reversed()) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
        let msg = (obj["message"] as? [String: Any]) ?? obj
        let role = (msg["role"] as? String) ?? (obj["type"] as? String)
        guard role == "user", let text = extractText(msg["content"]) ?? extractText(obj["content"]) else { continue }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty || clean.hasPrefix("<") { continue } // skip system-reminder / tool blocks
        return clean
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
        cwd: obj?["cwd"] as? String, terminal: terminal,
        sessionId: (obj?["session-id"] as? String) ?? "codex"
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
    let transcript = obj["transcript_path"] as? String
    let msg = VNInbound(type: .request, source: "claude", event: event,
                        title: oneLine(userText(transcript, first: true)), tool: tool, detail: summarize(toolInput),
                        commandDescription: toolInput?["description"] as? String,
                        userMessage: oneLine(userText(transcript, first: false)),
                        cwd: cwd, terminal: terminal,
                        model: lastAssistantModel(transcript), sessionId: sessionId)
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

// Activity update — fold this event into the session's live state.
let transcript = obj["transcript_path"] as? String
let task = oneLine(userText(transcript, first: true))
let lastUser = oneLine(userText(transcript, first: false))
let activityDetail: String?
switch event {
case "PreToolUse":            activityDetail = summarize(toolInput)
case "Notification":          activityDetail = obj["message"] as? String
case "Stop":                  activityDetail = oneLine(lastAssistantText(transcript))
case "SessionStart", "UserPromptSubmit", "PostToolUse", "SessionEnd": activityDetail = nil
default:                      exit(0) // ignore anything else
}
let msg = VNInbound(type: .notify, source: "claude", event: event,
                    title: task, tool: (event == "PreToolUse" ? tool : nil),
                    detail: activityDetail, userMessage: lastUser,
                    cwd: cwd, terminal: terminal,
                    model: lastAssistantModel(transcript), sessionId: sessionId)
_ = IPCClient.send(msg)
exit(0)
