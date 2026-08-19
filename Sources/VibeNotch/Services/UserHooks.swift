import Foundation
import VibeNotchCore

/// Meta-hooks: users drop executables into ~/.vibenotch/hooks named
/// on-<event>.sh (approval, stop, waiting, escalation) and we fire them with
/// one JSON argument. Fail-silent; vibe-notch becomes scriptable infrastructure.
enum UserHooks {
    static func fire(_ event: String, _ payload: [String: Any]) {
        let script = VNPaths.home.appendingPathComponent("hooks/on-\(event).sh")
        guard FileManager.default.isExecutableFile(atPath: script.path) else { return }
        let p = Process()
        p.executableURL = script
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let json = String(data: data, encoding: .utf8) {
            p.arguments = [json]
        }
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
