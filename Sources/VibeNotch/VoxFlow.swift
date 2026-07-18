import AVFoundation
import Speech

/// Voice → text. Records the mic and transcribes on-device (Apple Speech).
/// Auto-stops after a short silence; delivers the final text via `onFinal`.
@MainActor
final class VoxFlow: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var transcript = ""
    var onFinal: ((String) -> Void)?

    /// Live input level 0…1 — drives the notch waveform while dictating.
    @Published private(set) var level: Float = 0

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
        ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silence: Timer?

    func toggle() { listening ? stop(send: true) : start() }

    func start() {
        // Both callbacks land on background queues — @Sendable stops them
        // inheriting our @MainActor isolation (that inheritance was a SIGTRAP).
        AVCaptureDevice.requestAccess(for: .audio) { @Sendable [weak self] micOK in
            guard micOK else { NSLog("VoxFlow: microphone not authorized"); return }
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                Task { @MainActor in
                    guard status == .authorized else { NSLog("VoxFlow: speech not authorized"); return }
                    self?.begin()
                }
            }
        }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable, !listening else { return }
        transcript = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        // On-device only: no audio ever leaves the Mac.
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            NSLog("VoxFlow: no usable microphone input (format \(format))")
            cleanup()
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            req.append(buffer)
            // RMS → level for the waveform
            if let data = buffer.floatChannelData?[0] {
                let n = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<n { sum += data[i] * data[i] }
                let rms = n > 0 ? sqrtf(sum / Float(n)) : 0
                Task { @MainActor in self?.level = min(1, rms * 12) }
            }
        }
        engine.prepare()
        do { try engine.start() } catch { NSLog("VoxFlow: engine failed: \(error)"); cleanup(); return }
        listening = true
        resetSilence()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.resetSilence()
                }
                if error != nil || (result?.isFinal ?? false) { self.stop(send: true) }
            }
        }
    }

    func stop(send: Bool) {
        guard listening else { return }
        listening = false
        level = 0
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        request?.endAudio()
        cleanup()
        if send && !text.isEmpty { onFinal?(text) }
    }

    private func cleanup() {
        silence?.invalidate(); silence = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel(); task = nil
        request = nil
    }

    private func resetSilence() {
        silence?.invalidate()
        silence = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop(send: true) }
        }
    }
}
