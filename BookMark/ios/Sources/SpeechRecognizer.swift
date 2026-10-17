import Foundation
import Speech
import AVFoundation

// メモの音声入力（Speechフレームワーク）。
// 端末内認識が使える場合はそれを優先する（プライバシー・オフライン）。
@Observable
final class SpeechRecognizer {
    var transcript = ""
    var isRecording = false
    var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    /// 録音開始時点の文字列（続きから追記するため）
    private var base = ""

    var isSupported: Bool { recognizer != nil }

    func toggle(base current: String, onUpdate: @escaping (String) -> Void) {
        if isRecording { stop() } else { start(base: current, onUpdate: onUpdate) }
    }

    private func start(base current: String, onUpdate: @escaping (String) -> Void) {
        base = current
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else {
                DispatchQueue.main.async { self?.errorMessage = "音声認識が許可されていません" }
                return
            }
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    guard granted else { self?.errorMessage = "マイクが許可されていません"; return }
                    self?.beginSession(onUpdate: onUpdate)
                }
            }
        }
    }

    private func beginSession(onUpdate: @escaping (String) -> Void) {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "この端末では音声認識を利用できません"; return
        }
        stop()
        errorMessage = nil

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true   // 端末内認識を優先
        }
        request = req

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "マイクを準備できませんでした"; return
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch {
            errorMessage = "録音を開始できませんでした"; return
        }
        isRecording = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let spoken = result.bestTranscription.formattedString
                let combined = self.base.isEmpty ? spoken : self.base + " " + spoken
                DispatchQueue.main.async {
                    self.transcript = combined
                    onUpdate(combined)
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                DispatchQueue.main.async { self.stop() }
            }
        }
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
