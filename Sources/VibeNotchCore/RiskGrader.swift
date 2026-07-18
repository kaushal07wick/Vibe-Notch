import Foundation

public enum Risk: String, Codable, Sendable {
    case low, medium, high
}

/// Local heuristics for how dangerous a tool call looks. High risk should get
/// visible friction in the UI (red border, hold-to-approve).
public enum RiskGrader {
    static let highBash = [
        "rm -rf", "rm -fr", "sudo ", "curl ", "wget ", "| sh", "| bash", "|sh", "|bash",
        "--force", "push -f", "chmod 777", "dd if", "mkfs", "> /dev/", ":(){",
        "shutdown", "reboot", "diskutil erase", "killall", "launchctl",
    ]
    static let mediumBash = [
        "rm ", "mv ", "git push", "git reset --hard", "git clean", "npm publish",
        "pip install", "npm install -g", "brew install", "docker ", "kubectl ",
        "terraform ", "drop table", "delete from", "truncate ",
    ]
    static let sensitivePaths = [".env", "secret", "credential", "id_rsa", ".ssh/", "keychain"]

    public static func grade(tool: String?, detail: String?) -> Risk {
        let text = (detail ?? "").lowercased()
        switch tool {
        case "Bash", "Shell":
            if highBash.contains(where: text.contains) { return .high }
            if sensitivePaths.contains(where: text.contains) { return .high }
            if mediumBash.contains(where: text.contains) { return .medium }
            return .low
        case "Write", "Edit", "MultiEdit", "NotebookEdit":
            return sensitivePaths.contains(where: text.contains) ? .high : .low
        case "WebFetch", "Read", "Glob", "Grep", nil:
            return .low
        default:
            return .low
        }
    }
}
