import AppKit
import VibeNotchCore

// The control channel router — serves the CLI, web dashboard, and phone
// actions. One JSON line in, one out.
extension AppDelegate {
    /// CLI/dashboard command dispatch. Replies one JSON line.
    func handleControl(_ cmd: VNInbound) -> String {
        func fail(_ error: String) -> String { #"{"ok":false,"error":"\#(error)"}"# }
        func session(for target: String?) -> SessionActivity? {
            guard let target, !target.isEmpty else { return store.activeSession }
            return store.activeSessions.first {
                $0.sessionId.hasPrefix(target) || $0.folder == target
            }
        }
        switch cmd.event {
        case "list":
            var obj: [String: Any] = ["ok": true]
            obj["pending"] = store.pending.map {
                ["id": $0.id.uuidString, "tool": $0.inbound.tool ?? "",
                 "detail": $0.inbound.detail ?? "", "session": $0.inbound.sessionId ?? ""]
            }
            if let data = try? JSONEncoder().encode(store.activeSessions),
               let sessions = try? JSONSerialization.jsonObject(with: data) {
                obj["sessions"] = sessions
            }
            guard let out = try? JSONSerialization.data(withJSONObject: obj),
                  let text = String(data: out, encoding: .utf8) else { return fail("encoding") }
            return text
        case "approve_all":
            store.approveAll(sessionId: cmd.sessionId)
            return #"{"ok":true}"#
        case "undo":
            store.undoLast()
            return #"{"ok":true}"#
        case "approve", "deny":
            let match = cmd.sessionId == nil
                ? store.pending.first
                : store.pending.first { $0.inbound.sessionId?.hasPrefix(cmd.sessionId!) == true }
            guard let match else { return fail("no pending approval") }
            store.resolve(match, cmd.event == "approve" ? .allow : .deny)
            return #"{"ok":true}"#
        case "send":
            guard let s = session(for: cmd.sessionId), let text = cmd.detail else { return fail("no such session") }
            return TerminalControl.send(text, to: s) ? #"{"ok":true}"# : fail("terminal not injectable")
        case "interrupt":
            guard let s = session(for: cmd.sessionId) else { return fail("no such session") }
            return TerminalControl.interrupt(s) ? #"{"ok":true}"# : fail("no foreground process")
        default:
            return fail("unknown action")
        }
    }
}
