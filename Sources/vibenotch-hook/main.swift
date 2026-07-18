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

/// The real terminal output from a PostToolUse payload's `tool_response`.
func toolOutput(_ obj: [String: Any]) -> String? {
    guard let resp = obj["tool_response"] else { return nil }
    if let s = resp as? String { return s.isEmpty ? nil : s }
    if let d = resp as? [String: Any] {
        for key in ["stdout", "output", "content", "result", "stderr"] {
            if let s = d[key] as? String, !s.isEmpty { return s }
        }
        if let arr = d["content"] as? [[String: Any]] {
            let text = arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !text.isEmpty { return text }
        }
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

private func shell(_ path: String, _ args: [String]) -> String? {
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

let source = argValue(after: "--source") ?? "claude"
let (terminal, termMeta) = detectTerminal()

// Every agent sends hook JSON on stdin — except legacy Codex `notify`,
// which passes the payload as the last argv instead.
let stdinData = FileHandle.standardInput.readDataToEndOfFile()
let obj = (try? JSONSerialization.jsonObject(with: stdinData)) as? [String: Any] ?? [:]

if source == "codex" && obj["hook_event_name"] == nil {
    let payload = CommandLine.arguments.last.flatMap { $0.data(using: .utf8) } ?? Data()
    let legacy = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
    let msg = VNInbound(
        type: .notify, source: "codex",
        event: (legacy?["type"] as? String) ?? "agent-turn-complete",
        title: "Codex is waiting",
        detail: legacy?["last-assistant-message"] as? String,
        cwd: legacy?["cwd"] as? String, terminal: terminal,
        sessionId: (legacy?["session-id"] as? String) ?? "codex"
    )
    _ = IPCClient.send(msg)
    exit(0)
}

/// First present key, snake_case or camelCase (Cursor uses camelCase).
let field: ([String]) -> Any? = { keys in
    for k in keys where obj[k] != nil { return obj[k] }
    return nil
}

if source == "gemini" {
    // Gemini CLI: same settings.json shape, its own event names → map to ours.
    let raw = field(["hook_event_name", "hookEventName"]) as? String ?? "Unknown"
    let mapped: String
    switch raw {
    case "BeforeAgent": mapped = "UserPromptSubmit"
    case "AfterAgent": mapped = "Stop"
    case "SessionStart", "SessionEnd", "Notification": mapped = raw
    default: exit(0)
    }
    let msg = VNInbound(type: .notify, source: "gemini", event: mapped,
                        title: oneLine(field(["prompt"]) as? String),
                        detail: (field(["message"]) as? String) ?? oneLine(field(["prompt_response", "promptResponse"]) as? String),
                        userMessage: oneLine(field(["prompt"]) as? String),
                        cwd: field(["cwd"]) as? String, terminal: terminal,
                        sessionId: field(["session_id", "sessionID"]) as? String)
    _ = IPCClient.send(msg)
    exit(0)
}

if source == "cursor" {
    let raw = field(["hook_event_name", "hookEventName"]) as? String ?? "Unknown"
    let mapped: String
    var tool: String?
    var detail: String?
    switch raw {
    case "beforeSubmitPrompt": mapped = "UserPromptSubmit"
    case "beforeShellExecution":
        mapped = "PreToolUse"; tool = "Shell"; detail = field(["command"]) as? String
    case "afterFileEdit":
        mapped = "PostToolUse"; tool = "Edit"; detail = field(["file_path", "filePath"]) as? String
    case "stop": mapped = "Stop"
    default: exit(0)
    }
    let workspaces = field(["workspace_roots", "workspaceRoots"]) as? [String]
    let msg = VNInbound(type: .notify, source: "cursor", event: mapped,
                        tool: tool, detail: detail,
                        userMessage: oneLine(field(["prompt"]) as? String),
                        cwd: (field(["cwd"]) as? String) ?? workspaces?.first, terminal: terminal,
                        sessionId: field(["conversation_id", "conversationId"]) as? String)
    _ = IPCClient.send(msg)
    exit(0)
}

// Claude-schema family (claude, qwen, qoder, droid, codebuddy): identical payloads.
let event = obj["hook_event_name"] as? String ?? "Unknown"
let tool = obj["tool_name"] as? String
let toolInput = obj["tool_input"] as? [String: Any]
let cwd = obj["cwd"] as? String
let sessionId = obj["session_id"] as? String

/// AskUserQuestion's multiple-choice payload, if present.
func parseQuestions(_ input: [String: Any]?) -> [VNQuestion]? {
    guard let raw = input?["questions"] as? [[String: Any]], !raw.isEmpty else { return nil }
    let questions = raw.compactMap { q -> VNQuestion? in
        guard let text = q["question"] as? String else { return nil }
        let options = (q["options"] as? [[String: Any]] ?? []).compactMap { o -> VNQuestion.Option? in
            guard let label = o["label"] as? String else { return nil }
            return .init(label: label, description: o["description"] as? String)
        }
        return VNQuestion(question: text, header: q["header"] as? String,
                          multiSelect: q["multiSelect"] as? Bool ?? false, options: options)
    }
    return questions.isEmpty ? nil : questions
}

/// Emit the PermissionRequest decision in the agent's dialect. Answers
/// (AskUserQuestion) ride along as updatedInput for Claude-schema agents.
func emitDecision(_ behavior: String, answers: [String]?, originalInput: [String: Any]?) {
    var decision: [String: Any] = ["behavior": behavior]
    if source != "codex", let answers, var input = originalInput {
        input["answers"] = answers.map { [$0] } // one selected label per question
        decision["updatedInput"] = input
    }
    let inner: [String: Any] = ["hookEventName": "PermissionRequest", "decision": decision]
    let payload: [String: Any] = source == "codex"
        ? ["continue": true, "hookSpecificOutput": inner]  // Codex envelope
        : ["hookSpecificOutput": inner]                     // Claude schema
    if let data = try? JSONSerialization.data(withJSONObject: payload),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

if event == "PermissionRequest" {
    let transcript = obj["transcript_path"] as? String
    let msg = VNInbound(type: .request, source: source, event: event,
                        title: oneLine(userText(transcript, first: true)), tool: tool, detail: summarize(toolInput),
                        commandDescription: toolInput?["description"] as? String,
                        plan: toolInput?["plan"] as? String,
                        questions: parseQuestions(toolInput),
                        userMessage: oneLine(userText(transcript, first: false)),
                        cwd: cwd, terminal: terminal, tty: ttyName(),
                        termMeta: termMeta.isEmpty ? nil : termMeta,
                        model: lastAssistantModel(transcript), sessionId: sessionId)
    let reply = IPCClient.send(msg)
    switch reply?.decision.agentBehavior {
    case .allow: emitDecision("allow", answers: reply?.answers, originalInput: toolInput)
    case .deny: emitDecision("deny", answers: nil, originalInput: nil)
    default: break // no output → defer to the agent's own permission flow (fail-open)
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
case "PostToolUse",
     "PostToolUseFailure":    activityDetail = toolOutput(obj).map { String($0.prefix(1200)) }
case "Notification":          activityDetail = obj["message"] as? String
case "Stop", "StopFailure":   activityDetail = lastAssistantText(transcript).map { String($0.prefix(1200)) }
case "SessionStart", "UserPromptSubmit", "SessionEnd",
     "SubagentStart", "SubagentStop", "PreCompact": activityDetail = nil
default:                      exit(0) // ignore anything else
}
let msg = VNInbound(type: .notify, source: source, event: event,
                    title: task, tool: (event == "PreToolUse" || event == "PostToolUse") ? tool : nil,
                    detail: activityDetail, userMessage: lastUser,
                    cwd: cwd, terminal: terminal, tty: ttyName(),
                    termMeta: termMeta.isEmpty ? nil : termMeta,
                    model: lastAssistantModel(transcript), sessionId: sessionId)
_ = IPCClient.send(msg)
exit(0)
