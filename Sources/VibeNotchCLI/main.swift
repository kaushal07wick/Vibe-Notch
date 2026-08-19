import Foundation
import VibeNotchCore

// vibenotch — CLI for the notch app's socket. Scriptable from anywhere
// (Raycast, ssh, shell aliases):
//   vibenotch list                     sessions + pending approvals (JSON)
//   vibenotch approve | deny           decide the front permission card
//   vibenotch send <session> <text…>   type a reply into a session's terminal
//   vibenotch interrupt <session>      ^C a session's foreground process
//   vibenotch model <session> <name>   switch that session's model
//   vibenotch approve_all | undo       batch approve / take the last one back
//   vibenotch open [seconds]           hold the panel open without a pointer

let args = CommandLine.arguments.dropFirst()
guard let action = args.first,
      ["list", "approve", "deny", "send", "interrupt",
       "model", "approve_all", "undo", "open"].contains(action) else {
    // The app answered model/approve_all/undo all along; the CLI just refused
    // to send them.
    print("""
    usage: vibenotch list | approve | deny | approve_all | undo
           vibenotch send <session> <text…> | model <session> <name>
           vibenotch interrupt <session> | open [seconds]
    """)
    exit(2)
}

let target = args.dropFirst().first
let text = args.dropFirst(2).joined(separator: " ")

// `open` takes seconds, not a session.
let msg = VNInbound(type: .control, source: "cli", event: action,
                    detail: action == "open" ? target : (text.isEmpty ? nil : text),
                    sessionId: action == "open" ? nil : target)
guard let reply = IPCClient.sendControl(msg) else {
    FileHandle.standardError.write(Data("vibenotch: app not running (socket unreachable)\n".utf8))
    exit(1)
}
print(reply)
exit(reply.contains(#""ok":false"#) ? 1 : 0)
