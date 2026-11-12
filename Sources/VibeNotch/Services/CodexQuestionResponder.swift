import Foundation
import VibeNotchCore

enum CodexQuestionResponder {
    static func send(_ reply: String, sessionID: String) async -> Bool {
        guard let script = Bundle.main.url(forResource: "vibenotch-codex-reply", withExtension: "py"),
              var data = try? JSONSerialization.data(withJSONObject: ["threadId": sessionID, "text": reply]) else { return false }
        data.append(0x0A)
        // The generic executor waits for an acknowledged successful exit with a
        // hard deadline; stdin is private and never added to the command line.
        return await TerminalCommand.run([["/usr/bin/env", "python3", script.path]], timeout: 15, input: data)
    }
}
