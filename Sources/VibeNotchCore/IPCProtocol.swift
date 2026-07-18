import Foundation

/// Line-delimited JSON messages between the `vibenotch-hook` client and the app,
/// carried over the Unix socket at `VNPaths.socket`.

public enum VNMessageType: String, Codable, Sendable {
    case notify   // fire-and-forget; server acks by closing
    case request  // needs a decision; connection stays open until the app replies
}

/// A message from the hook client to the app.
public struct VNInbound: Codable, Sendable {
    public var type: VNMessageType
    public var source: String     // "claude" | "codex"
    public var event: String      // hook event name, e.g. "PermissionRequest", "Stop"
    public var tool: String?      // tool name, for approvals
    public var detail: String?    // command / file path / message preview
    public var cwd: String?
    public var sessionId: String?

    public init(type: VNMessageType, source: String, event: String,
                tool: String? = nil, detail: String? = nil,
                cwd: String? = nil, sessionId: String? = nil) {
        self.type = type
        self.source = source
        self.event = event
        self.tool = tool
        self.detail = detail
        self.cwd = cwd
        self.sessionId = sessionId
    }
}

public enum VNDecision: String, Codable, Sendable {
    case allow, deny, ask
}

/// The app's reply to a `request`.
public struct VNReply: Codable, Sendable {
    public var decision: VNDecision
    public init(decision: VNDecision) { self.decision = decision }
}
