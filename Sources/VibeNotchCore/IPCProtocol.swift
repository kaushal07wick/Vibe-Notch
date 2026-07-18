import Foundation

/// Line-delimited JSON messages between the `vibenotch-hook` client and the app,
/// carried over the Unix socket at `VNPaths.socket`.

public enum VNMessageType: String, Codable, Sendable {
    case notify   // fire-and-forget; server acks by closing
    case request  // needs a decision; connection stays open until the app replies
    case control  // CLI/dashboard command; server replies one JSON line
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
    public var questions: [VNQuestion]?    // AskUserQuestion multiple-choice payload
    public var userMessage: String?        // the last user message ("You: …")
    public var cwd: String?
    public var terminal: String?           // display name of the terminal, e.g. "Ghostty"
    public var tty: String?                // session tty, e.g. "ttys014" — for exact-tab jump
    public var termMeta: [String: String]? // pane/window ids for precise jumps (tmux/wezterm/kitty)
    public var model: String?              // friendly model name, e.g. "Opus 4.8"
    public var host: String?               // remote hostname when tunneled over SSH
    public var gitBranch: String?          // current branch of cwd
    public var gitDirty: Bool?             // uncommitted changes present
    public var tokensIn: Int?              // input tokens of the latest turn
    public var tokensOut: Int?             // output tokens of the latest turn
    public var sessionId: String?

    public init(type: VNMessageType, source: String, event: String,
                title: String? = nil, tool: String? = nil, detail: String? = nil,
                commandDescription: String? = nil, plan: String? = nil,
                questions: [VNQuestion]? = nil, userMessage: String? = nil,
                cwd: String? = nil, terminal: String? = nil, tty: String? = nil,
                termMeta: [String: String]? = nil,
                model: String? = nil, host: String? = nil,
                gitBranch: String? = nil, gitDirty: Bool? = nil,
                tokensIn: Int? = nil, tokensOut: Int? = nil, sessionId: String? = nil) {
        self.type = type
        self.source = source
        self.event = event
        self.title = title
        self.tool = tool
        self.detail = detail
        self.commandDescription = commandDescription
        self.plan = plan
        self.questions = questions
        self.userMessage = userMessage
        self.cwd = cwd
        self.terminal = terminal
        self.tty = tty
        self.termMeta = termMeta
        self.model = model
        self.host = host
        self.gitBranch = gitBranch
        self.gitDirty = gitDirty
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.sessionId = sessionId
    }
}

public enum VNDecision: String, Codable, Sendable {
    case allow, deny, ask
    case alwaysAllow   // allow + persist a permission rule for this tool/command
    case bypass        // allow + auto-approve the rest of this session

    /// What the agent is told — the richer cases all resolve to allow.
    public var agentBehavior: VNDecision { self == .deny || self == .ask ? self : .allow }
}

/// A multiple-choice question from AskUserQuestion, passed through for the
/// notch to render.
public struct VNQuestion: Codable, Sendable {
    public struct Option: Codable, Sendable {
        public var label: String
        public var description: String?
        public init(label: String, description: String? = nil) {
            self.label = label
            self.description = description
        }
    }
    public var question: String
    public var header: String?
    public var multiSelect: Bool
    public var options: [Option]
    public init(question: String, header: String? = nil, multiSelect: Bool = false, options: [Option]) {
        self.question = question
        self.header = header
        self.multiSelect = multiSelect
        self.options = options
    }
}

/// The app's reply to a `request`.
public struct VNReply: Codable, Sendable {
    public var decision: VNDecision
    /// Selected option label per question (AskUserQuestion), in question order.
    public var answers: [String]?
    public init(decision: VNDecision, answers: [String]? = nil) {
        self.decision = decision
        self.answers = answers
    }
}
