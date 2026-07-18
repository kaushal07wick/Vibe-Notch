import Foundation
import VibeNotchCore

// Tool-input/-output extraction helpers.

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

/// Branch + dirty state for the working directory. HEAD is a file read;
/// dirtiness costs one fast `git status` — only called on the sparse events.
func gitInfo(_ cwd: String?) -> (branch: String?, dirty: Bool?) {
    guard let cwd else { return (nil, nil) }
    guard let head = try? String(contentsOfFile: cwd + "/.git/HEAD", encoding: .utf8) else { return (nil, nil) }
    let branch = head.hasPrefix("ref: refs/heads/")
        ? head.dropFirst("ref: refs/heads/".count).trimmingCharacters(in: .whitespacesAndNewlines)
        : String(head.prefix(8))
    let porcelain = shell("/usr/bin/git", ["-C", cwd, "status", "--porcelain", "--untracked-files=no"])
    return (branch, porcelain.map { !$0.isEmpty })
}
