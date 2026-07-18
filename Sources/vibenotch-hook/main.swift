import Foundation
import VibeNotchCore

// vibenotch-hook: the client wired into agent configs. FAIL-OPEN ALWAYS — if the app
// is down or anything errors, exit 0 with no decision so the agent proceeds normally.

func argValue(after flag: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
    return a[i + 1]
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
    let transcript = Transcript(obj["transcript_path"] as? String)
    let msg = VNInbound(type: .request, source: source, event: event,
                        title: oneLine(userText(transcript, first: true)), tool: tool, detail: summarize(toolInput),
                        commandDescription: toolInput?["description"] as? String,
                        plan: toolInput?["plan"] as? String,
                        diffOld: toolInput?["old_string"] as? String,
                        diffNew: (toolInput?["new_string"] as? String) ?? (tool == "Write" ? toolInput?["content"] as? String : nil),
                        questions: parseQuestions(toolInput),
                        userMessage: oneLine(userText(transcript, first: false)),
                        cwd: cwd, terminal: terminal, tty: ttyName(),
                        termMeta: termMeta.isEmpty ? nil : termMeta,
                        model: lastAssistantModel(transcript),
                        gitBranch: gitInfo(cwd).branch, gitDirty: gitInfo(cwd).dirty,
                        sessionId: sessionId)
    let reply = IPCClient.send(msg)
    if reply == nil {
        // Evidence trail for "the notch missed a permission": app unreachable
        // or no decision — the agent's own prompt takes over either way.
        let line = "\(ISO8601DateFormatter().string(from: Date())) source=\(source) tool=\(tool ?? "?") sid=\(sessionId ?? "?")\n"
        let log = VNPaths.data.appendingPathComponent("missed-permissions.log")
        if let handle = try? FileHandle(forWritingTo: log) {
            _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data(line.utf8)); try? handle.close()
        } else {
            try? line.write(to: log, atomically: true, encoding: .utf8)
        }
    }
    switch reply?.decision.agentBehavior {
    case .allow: emitDecision("allow", answers: reply?.answers, originalInput: toolInput)
    case .deny: emitDecision("deny", answers: nil, originalInput: nil)
    default: break // no output → defer to the agent's own permission flow (fail-open)
    }
    exit(0)
}

// Activity update — fold this event into the session's live state.
let transcript = Transcript(obj["transcript_path"] as? String)
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
let git = ["SessionStart", "UserPromptSubmit", "Stop"].contains(event) ? gitInfo(cwd) : (nil, nil)
let usage = event == "Stop" ? latestUsage(transcript) : (nil, nil)
let msg = VNInbound(type: .notify, source: source, event: event,
                    title: task, tool: (event == "PreToolUse" || event == "PostToolUse") ? tool : nil,
                    detail: activityDetail, userMessage: lastUser,
                    cwd: cwd, terminal: terminal, tty: ttyName(),
                    termMeta: termMeta.isEmpty ? nil : termMeta,
                    model: lastAssistantModel(transcript),
                    gitBranch: git.0, gitDirty: git.1,
                    tokensIn: usage.0, tokensOut: usage.1, sessionId: sessionId)
_ = IPCClient.send(msg)
exit(0)
