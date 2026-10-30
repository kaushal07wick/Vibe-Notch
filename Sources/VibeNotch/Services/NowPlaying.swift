import AppKit

/// What Music or Spotify is playing, and the transport controls. macOS 15.4 closed the
/// system-wide now-playing API to third-party apps, so this asks the two players directly
/// (only if they're already running — it never launches one).
@MainActor
final class NowPlaying: ObservableObject {
    static let shared = NowPlaying()
    @Published var title = ""
    @Published var artist = ""
    @Published var playing = false
    @Published var artwork: NSImage?
    @Published var app: String?          // "Music" | "Spotify"
    private var lastTrack = ""
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

    func refresh() {
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
        app = name; title = t; artist = a; playing = isPlaying
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
        VNAppleScript.run("tell application \"\(app)\" to \(command.rawValue)", purpose: "controlling playback")
        Task { try? await Task.sleep(for: .milliseconds(250)); refresh() }
    }
}
