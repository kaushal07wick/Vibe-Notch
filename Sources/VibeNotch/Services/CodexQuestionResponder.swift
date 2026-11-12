import Foundation
import VibeNotchCore

enum CodexQuestionResponder {
    static func send(_ reply: String, sessionID: String) async -> Bool {
        guard let script = Bundle.main.url(forResource: "vibenotch-codex-reply", withExtension: "py"),
              var data = try? JSONSerialization.data(withJSONObject: ["threadId": sessionID, "text": reply]) else { return false }
        data.append(0x0A)
        return await Task.detached { [data] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", script.path]
            let input = Pipe()
            process.standardInput = input
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                try input.fileHandleForWriting.write(contentsOf: data)
                try input.fileHandleForWriting.close()
            } catch {
                if process.isRunning { process.terminate() }
                return false
            }
            let deadline = Date().addingTimeInterval(15)
            while process.isRunning && Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
            if process.isRunning {
                process.terminate()
                try? await Task.sleep(for: .milliseconds(50))
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                return false
            }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }.value
    }
}
