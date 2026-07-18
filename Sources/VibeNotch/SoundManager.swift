import AppKit
import VibeNotchCore

/// 8-bit style alert tones, synthesized at runtime (square waves → chiptune feel).
/// No bundled audio assets, no licensing.
enum VNSound {
    case permission, waiting, done

    /// Per-theme note tables. "chime" = soft bells, "arcade" = 8-bit squares,
    /// "minimal" = one quiet tick for everything.
    func notes(theme: String) -> (notes: [(freq: Double, ms: Int)], square: Bool) {
        switch (theme, self) {
        case ("arcade", .permission): return ([(660, 70), (990, 70), (1320, 120)], true)
        case ("arcade", .waiting):    return ([(523, 90), (392, 120)], true)
        case ("arcade", .done):       return ([(784, 60), (988, 60), (1175, 60), (1568, 150)], true)
        case ("minimal", _):          return ([(1200, 70)], false)
        case (_, .permission):        return ([(880, 95), (1318.5, 320)], false)
        case (_, .waiting):           return ([(1046.5, 260)], false)
        case (_, .done):              return ([(1046.5, 95), (1318.5, 95), (1568, 340)], false)
        }
    }
}

@MainActor
final class SoundManager {
    static let shared = SoundManager()
    var enabled: Bool {
        get { VNSettings.soundEnabled }
        set { VNSettings.soundEnabled = newValue }
    }
    private var cache: [String: NSSound] = [:]

    func play(_ sound: VNSound) {
        guard enabled else { return }
        let key = "\(sound)-\(VNSettings.soundTheme)"
        let ns = cache[key] ?? customSound(for: sound) ?? NSSound(data: Self.wav(for: sound, theme: VNSettings.soundTheme))
        cache[key] = ns
        ns?.volume = Float(VNSettings.soundVolume)
        ns?.stop()
        ns?.play()
    }

    /// Custom sound pack: drop `permission.wav` / `waiting.wav` / `done.wav`
    /// (or .aiff/.mp3/.m4a) into ~/.vibenotch/sounds to override the synth tones.
    private func customSound(for sound: VNSound) -> NSSound? {
        let dir = VNPaths.home.appendingPathComponent("sounds")
        for ext in ["wav", "aiff", "mp3", "m4a"] {
            let url = dir.appendingPathComponent("\(sound).\(ext)")
            if FileManager.default.fileExists(atPath: url.path),
               let ns = NSSound(contentsOf: url, byReference: true) { return ns }
        }
        return nil
    }

    // MARK: WAV synthesis

    private static func wav(for sound: VNSound, theme: String) -> Data {
        let sampleRate = 44_100
        var samples: [Int16] = []
        let (notes, square) = sound.notes(theme: theme)
        for note in notes {
            let count = sampleRate * note.ms / 1000
            for i in 0..<count {
                let t = Double(i) / Double(sampleRate)
                let attack = min(1.0, t / 0.006)                            // 6ms soft attack, no click
                let decay = exp(-t * 6.5)                                   // bell-like fade
                let sine = sin(2 * .pi * note.freq * t)
                let wave = square
                    ? (sine >= 0 ? 0.7 : -0.7)                              // 8-bit square
                    : sine + 0.28 * sin(2 * .pi * note.freq * 2 * t)        // bell warmth
                let s = wave * attack * decay * 0.34
                samples.append(Int16(max(-1, min(1, s)) * 32_767))
            }
        }
        return pcmWav(samples, sampleRate: sampleRate)
    }

    private static func pcmWav(_ samples: [Int16], sampleRate: Int) -> Data {
        var d = Data()
        func str(_ s: String) { d.append(s.data(using: .ascii)!) }
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        let bytes = samples.count * 2
        str("RIFF"); u32(36 + bytes); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(1); u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        str("data"); u32(bytes)
        for s in samples { var x = s.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        return d
    }
}
