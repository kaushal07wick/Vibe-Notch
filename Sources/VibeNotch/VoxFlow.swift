import AVFoundation
import Speech

/// Voice → text. Records the mic and transcribes on-device (Apple Speech).
/// Auto-stops after a short silence; delivers the final text via `onFinal`.
@MainActor
final class VoxFlow: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var transcript = ""
    var onFinal: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silence: Timer?

    func toggle() { listening ? stop(send: true) : start() }

    func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard status == .authorized else { NSLog("VoxFlow: speech not authorized"); return }
                self?.begin()
            }
        }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable, !listening else { return }
        transcript = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            req.append(buffer)
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
