import AppKit

/// 8-bit style alert tones, synthesized at runtime (square waves → chiptune feel).
/// No bundled audio assets, no licensing.
enum VNSound {
    case permission, waiting, done

    var notes: [(freq: Double, ms: Int)] {
        switch self {
        case .permission: return [(660, 80), (990, 130)]   // rising "hey, look"
        case .waiting:    return [(523, 120)]              // single mid ping
        case .done:       return [(784, 70), (1046, 120)]  // happy two-note
        }
    }
}

@MainActor
final class SoundManager {
    static let shared = SoundManager()
    var enabled = true
    private var cache: [String: NSSound] = [:]

    func play(_ sound: VNSound) {
        guard enabled else { return }
        let key = "\(sound)"
        let ns = cache[key] ?? NSSound(data: Self.wav(for: sound))
        cache[key] = ns
        ns?.stop()
        ns?.play()
    }

    // MARK: WAV synthesis

    private static func wav(for sound: VNSound) -> Data {
        let sampleRate = 22_050
        var samples: [Int16] = []
        for note in sound.notes {
            let count = sampleRate * note.ms / 1000
            let period = Double(sampleRate) / note.freq
            for i in 0..<count {
                let square: Double = i.truncatingPhase(period) < period / 2 ? 1 : -1
                let fade = min(1.0, Double(min(i, count - i)) / 220.0) // avoid clicks
                samples.append(Int16(square * 0.22 * fade * 32_767))
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

private extension Int {
    /// Phase within one wave period.
    func truncatingPhase(_ period: Double) -> Double { Double(self).truncatingRemainder(dividingBy: period) }
}
