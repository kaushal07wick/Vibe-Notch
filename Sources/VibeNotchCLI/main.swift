import Foundation
import VibeNotchCore

// vibenotch — CLI for the notch app's socket. Scriptable from anywhere
// (Raycast, ssh, shell aliases):
//   vibenotch list                     sessions + pending approvals (JSON)
//   vibenotch approve | deny           decide the front permission card
//   vibenotch send <session> <text…>   type a reply into a session's terminal
//   vibenotch interrupt <session>      ^C a session's foreground process

let args = CommandLine.arguments.dropFirst()
guard let action = args.first,
      ["list", "approve", "deny", "send", "interrupt"].contains(action) else {
    print("usage: vibenotch list | approve | deny | send <session> <text…> | interrupt <session>")
    exit(2)
}

let target = args.dropFirst().first
let text = args.dropFirst(2).joined(separator: " ")

let msg = VNInbound(type: .control, source: "cli", event: action,
                    detail: text.isEmpty ? nil : text, sessionId: target)
guard let reply = IPCClient.sendControl(msg) else {
    FileHandle.standardError.write(Data("vibenotch: app not running (socket unreachable)\n".utf8))
    exit(1)
}
print(reply)
exit(reply.contains(#""ok":false"#) ? 1 : 0)
