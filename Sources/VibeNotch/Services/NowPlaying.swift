import AppKit

/// What's playing, and the transport controls. macOS 15.4 closed the system-wide now-playing
/// API to third-party apps, but still serves Apple's own /usr/bin/perl — so a tiny bridge
/// dylib (Resources/NowPlayingBridge.m) is loaded through perl to read any source, browsers
/// included. If that fails, Music and Spotify are asked directly over AppleScript.
@MainActor
final class NowPlaying: ObservableObject {
    static let shared = NowPlaying()
    @Published var title = ""
    @Published var artist = ""
    @Published var playing = false
    @Published var artwork: NSImage?
    @Published var app: String?          // "System" (bridge) | "Music" | "Spotify"
    private var lastTrack = ""
    /// After a click the icon flips at once; readings older than the command are ignored until then.
    private var holdPlayingUntil = Date.distantPast
    private var timer: Timer?

    private static let bundles = ["Music": "com.apple.Music", "Spotify": "com.spotify.client"]

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in Task { @MainActor in self.refresh() } }
    }
    func stop() { timer?.invalidate(); timer = nil }

    private func running(_ name: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundles[name]!).isEmpty
    }

    /// Run one bridge entry point under /usr/bin/perl. Blocking — call off the main actor.
    nonisolated static func bridge(_ symbol: String, cmd: Int? = nil) -> Data? {
        let base = Bundle.main.bundleURL.appendingPathComponent("Contents")
        let lib = base.appendingPathComponent("Helpers/libvnnowplaying.dylib").path
        let pl = base.appendingPathComponent("Resources/nowplaying.pl").path
        guard FileManager.default.fileExists(atPath: lib) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [pl, lib, symbol]
        if let cmd { p.environment = ["VN_CMD": String(cmd)] }
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return data
    }

    func refresh() {
        Task.detached {
            let data = NowPlaying.bridge("vn_get")
            await MainActor.run { self.apply(data) }
        }
    }

    private func apply(_ data: Data?) {
        guard let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = j["title"] as? String, !t.isEmpty else { refreshScripted(); return }
        let a = j["artist"] as? String ?? ""
        app = "System"; title = t; artist = a
        if Date() > holdPlayingUntil { playing = (j["playing"] as? Bool) ?? ((j["playing"] as? Int) == 1) }
        if "System|\(t)|\(a)" != lastTrack {
            lastTrack = "System|\(t)|\(a)"
            artwork = (j["art"] as? String).flatMap { Data(base64Encoded: $0) }.flatMap(NSImage.init(data:))
        }
    }

    private func refreshScripted() {
        // prefer whichever is actually playing, else whichever is open
        var found: (String, String, String, Bool)?
        for name in ["Spotify", "Music"] where running(name) {
            let script = """
            tell application "\(name)"
                if player state is stopped then return ""
                return (player state as string) & "|||" & (name of current track) & "|||" & (artist of current track)
            end tell
            """
            guard let out = VNAppleScript.run(script, purpose: "reading what's playing"), !out.isEmpty else { continue }
            let p = out.components(separatedBy: "|||")
            guard p.count == 3 else { continue }
            let isPlaying = p[0] == "playing"
            if found == nil || isPlaying { found = (name, p[1], p[2], isPlaying) }
            if isPlaying { break }
        }
        guard let (name, t, a, isPlaying) = found else {
            app = nil; title = ""; artist = ""; playing = false; artwork = nil; lastTrack = ""
            return
        }
        app = name; title = t; artist = a
        if Date() > holdPlayingUntil { playing = isPlaying }
        if "\(name)|\(t)|\(a)" != lastTrack {
            lastTrack = "\(name)|\(t)|\(a)"
            artwork = loadArtwork(name)
        }
    }

    private func loadArtwork(_ name: String) -> NSImage? {
        if name == "Spotify" {
            guard let url = VNAppleScript.run(#"tell application "Spotify" to return artwork url of current track"#,
                                              purpose: "reading album art"),
                  let u = URL(string: url) else { return nil }
            return NSImage(contentsOf: u)
        }
        let path = NSTemporaryDirectory() + "vn-art.dat"
        let script = """
        tell application "Music"
            set d to raw data of artwork 1 of current track
        end tell
        set f to open for access POSIX file "\(path)" with write permission
        set eof f to 0
        write d to f
        close access f
        return "ok"
        """
        guard VNAppleScript.run(script, purpose: "reading album art") == "ok" else { return nil }
        return NSImage(contentsOfFile: path)
    }

    enum Command: String { case playpause, next = "next track", previous = "previous track" }
    func send(_ command: Command) {
        guard let app else { return }
        if command == .playpause { playing.toggle(); holdPlayingUntil = Date().addingTimeInterval(1.5) }
        if app == "System" {
            let code = command == .playpause ? 2 : command == .next ? 4 : 5
            Task.detached {
                _ = NowPlaying.bridge("vn_cmd", cmd: code)
                try? await Task.sleep(for: .milliseconds(300))
                await MainActor.run { self.refresh() }
            }
            return
        }
        VNAppleScript.run("tell application \"\(app)\" to \(command.rawValue)", purpose: "controlling playback")
        Task { try? await Task.sleep(for: .milliseconds(250)); refresh() }
    }
}
