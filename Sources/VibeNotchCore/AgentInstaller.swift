import Foundation

/// A coding agent we can wire the hook into. New agents = a new conformer.
public protocol AgentInstaller: Sendable {
    var id: String { get }          // "claude", "codex", …
    var displayName: String { get }
    var isConnected: Bool { get }
    func connect(hookBinarySource: URL) throws
    func disconnect() throws
    func reconcile() // re-apply on launch to pick up newly-added hook events
}

public struct ClaudeAgentInstaller: AgentInstaller {
    public init() {}
    public var id: String { "claude" }
    public var displayName: String { "Claude Code" }
    public var isConnected: Bool { ClaudeInstaller.isConnected }
    public func connect(hookBinarySource: URL) throws { try ClaudeInstaller.connect(hookBinarySource: hookBinarySource) }
    public func disconnect() throws { try ClaudeInstaller.disconnect() }
    public func reconcile() { ClaudeInstaller.reconcileIfConnected() }
}

public struct CodexAgentInstaller: AgentInstaller {
    public init() {}
    public var id: String { "codex" }
    public var displayName: String { "Codex" }
    public var isConnected: Bool { CodexInstaller.isConnected }
    public func connect(hookBinarySource: URL) throws { try CodexInstaller.connect(hookBinarySource: hookBinarySource) }
    public func disconnect() throws { try CodexInstaller.disconnect() }
    public func reconcile() {}
}

public enum AgentInstallers {
    /// All agents we can install today. Gemini/Cursor/Kimi land here as they're added.
    public static let all: [AgentInstaller] = [ClaudeAgentInstaller(), CodexAgentInstaller()]

    public static func byID(_ id: String) -> AgentInstaller? { all.first { $0.id == id } }
}
