import Foundation

/// User-editable auto-approve list for Bash commands. Conservative by design:
/// a pattern only matches a SIMPLE command (no `&&`, `;`, `|`, backticks,
/// subshells or redirects — compound commands can smuggle anything).
public enum SafeList {
    public static var url: URL { VNPaths.data.appendingPathComponent("safelist.json") }

    /// Read-only starters. Users add their own via the JSON file.
    public static let defaults = ["git status", "git diff", "git log", "ls", "pwd", "which"]

    public static func patterns() -> [String] {
        if let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            return list
        }
        save(defaults) // seed on first use so the file is there to edit
        return defaults
    }

    public static func save(_ patterns: [String]) {
        if let data = try? JSONEncoder().encode(patterns) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Pure matcher. `command` must be a simple invocation starting with a
    /// pattern ("git status", "git status -sb" — but never "ls && rm -rf x").
    public static func matches(_ command: String, patterns: [String]) -> Bool {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return false }
        for dangerous in ["&&", "||", ";", "|", "`", "$(", ">", "<", "\n"] {
            if cmd.contains(dangerous) { return false }
        }
        return patterns.contains { cmd == $0 || cmd.hasPrefix($0 + " ") }
    }
}
