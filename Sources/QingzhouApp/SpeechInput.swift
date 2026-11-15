import AVFoundation
import Foundation
import Speech

/// Speaking to 小轻舟: Apple's speech recognition in Chinese, on this Mac when it can. It listens
/// only while asked, shows the words as they come, and stops by itself after a short pause.
@MainActor
final class SpeechInput: ObservableObject {
    @Published var listening = false
    @Published var text = ""
    @Published var level: Float = 0          // loudness, for the little bars
    @Published var problem: String?

    init() {   // screenshot test: show the listening look without a microphone
        if CommandLine.arguments.contains("--show-listening") { listening = true; level = 0.8 }
    }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silence: Task<Void, Never>?
    private var finished: ((String) -> Void)?

    /// Starts listening; `done` gets the words once the owner stops talking (or taps again).
    func start(done: @escaping (String) -> Void) {
        guard !listening else { return }
        problem = nil
        text = ""
        finished = done
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.problem = "要先允许“语音识别”：系统设置 › 隐私与安全性 › 语音识别"
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor in
                        guard granted else {
                            self.problem = "要先允许用麦克风：系统设置 › 隐私与安全性 › 麦克风"
                            return
                        }
                        self.begin()
                    }
                }
            }
        }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else {
            problem = "这台电脑现在用不了中文语音识别，可以先打字"
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let level = Self.loudness(buffer)
            Task { @MainActor in self?.level = level }
        }
        engine.prepare()
        do { try engine.start() } catch {
            problem = "麦克风没打开：\(error.localizedDescription)"
            input.removeTap(onBus: 0)
            return
        }
        listening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.text = result.bestTranscription.formattedString
                    self.waitForPause()
                    if result.isFinal { self.stop() }
                } else if error != nil, self.listening {
                    self.stop()
                }
            }
        }
        waitForPause(seconds: 6)   // nothing said at all: give up after a while
    }

    /// Stops after a short pause in speaking.
    private func waitForPause(seconds: Double = 1.6) {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    /// Stops listening and hands over what was said.
    func stop() {
        guard listening else { return }
        listening = false
        silence?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        level = 0
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let done = finished
        finished = nil
        if !said.isEmpty { done?(said) }
    }

    nonisolated private static func loudness(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        return min(1, sqrt(sum / Float(buffer.frameLength)) * 12)
    }
}
