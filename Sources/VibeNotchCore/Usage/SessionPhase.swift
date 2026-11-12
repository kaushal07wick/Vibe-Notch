import Foundation

/// A display state derived from the last observed event. It does not establish
/// that an agent process is alive or that its permissions can be answered.
public enum SessionPhase: String, Codable, Sendable, CaseIterable {
    case working, waiting, completed, interrupted, failed, inactive, unknown

    public static let activityWindow: TimeInterval = 90

    public static func resolve(event: String, updatedAt: Date, now: Date = Date(),
                               hasPendingRequest: Bool = false) -> SessionPhase {
        if hasPendingRequest { return .waiting }
        switch event {
        case "Stop", "task_complete": return .completed
        case "Interrupted", "turn_aborted": return .interrupted
        case "StopFailure", "PostToolUseFailure": return .failed
        case "SessionEnd": return .inactive
        case "PreToolUse", "PostToolUse", "UserPromptSubmit", "PreCompact",
             "Notification", "PermissionRequest":
            guard now.timeIntervalSince(updatedAt) <= activityWindow else { return .inactive }
            return ["Notification", "PermissionRequest"].contains(event) ? .waiting : .working
        default: return .unknown
        }
    }

    public var label: String {
        switch self {
        case .working: return "Working"
        case .waiting: return "Needs you"
        case .completed: return "Finished"
        case .interrupted: return "Interrupted"
        case .failed: return "Failed"
        case .inactive: return "No recent activity"
        case .unknown: return "Status unavailable"
        }
    }

    public var isBusy: Bool { self == .working || self == .waiting }
    public var needsAttention: Bool { self == .waiting }

    public func statusText(event: String, tool: String? = nil) -> String {
        if self == .failed, event == "PostToolUseFailure" { return "\(tool ?? "Tool") failed" }
        guard self == .working else { return label }
        switch event {
        case "PreToolUse": return "Running \(tool ?? "tool")"
        case "UserPromptSubmit": return "Thinking…"
        case "PreCompact": return "Compacting context…"
        default: return label
        }
    }

    /// Requests needing a person come first; recent work follows them.
    public var sortPriority: Int {
        switch self {
        case .waiting: return 0
        case .working: return 1
        case .failed: return 2
        case .interrupted: return 3
        case .completed: return 4
        case .inactive, .unknown: return 5
        }
    }
}
