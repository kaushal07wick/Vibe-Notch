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
    public var title: String?     // brief label, e.g. "Claude finished", "waiting for input"
    public var tool: String?               // tool name, for approvals
    public var detail: String?             // full text — command, or the agent's last message
    public var commandDescription: String? // the agent's one-line explanation of the command
    public var plan: String?               // Markdown plan text (ExitPlanMode approvals)
    public var userMessage: String?        // the last user message ("You: …")
    public var cwd: String?
    public var terminal: String?           // display name of the terminal, e.g. "Ghostty"
    public var tty: String?                // session tty, e.g. "ttys014" — for exact-tab jump
    public var model: String?              // friendly model name, e.g. "Opus 4.8"
    public var sessionId: String?

    public init(type: VNMessageType, source: String, event: String,
                title: String? = nil, tool: String? = nil, detail: String? = nil,
                commandDescription: String? = nil, plan: String? = nil, userMessage: String? = nil,
                cwd: String? = nil, terminal: String? = nil, tty: String? = nil,
                model: String? = nil, sessionId: String? = nil) {
        self.type = type
        self.source = source
        self.event = event
        self.title = title
        self.tool = tool
        self.detail = detail
        self.commandDescription = commandDescription
        self.plan = plan
        self.userMessage = userMessage
        self.cwd = cwd
        self.terminal = terminal
        self.tty = tty
        self.model = model
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
