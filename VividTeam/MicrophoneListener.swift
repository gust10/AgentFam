// MicrophoneListener.swift
// Captures mic audio and delivers final utterances via SFSpeechRecognizer.
//
// Permissions needed in Info.plist:
//   NSMicrophoneUsageDescription
//   NSSpeechRecognitionUsageDescription

import Speech
import AVFoundation
import Observation

@Observable
final class MicrophoneListener {

    enum State { case idle, recording }

    private(set) var state: State = .idle
    private(set) var partial: String = ""

    /// Called with the final transcribed utterance after a pause.
    var onUtterance: ((String) -> Void)?

    private let recognizer: SFSpeechRecognizer = {
        guard let r = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            fatalError("SFSpeechRecognizer unavailable on this device")
        }
        return r
    }()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: - Permissions

    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            guard authStatus == .authorized else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    // MARK: - Start / Stop

    func start() throws {
        guard state == .idle, recognizer.isAvailable else { return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = false
        self.request = req

        let inputNode = audioEngine.inputNode
        let fmt = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak req] buf, _ in
            req?.append(buf)
        }

        recognitionTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async { self.partial = text }

                if result.isFinal {
                    self.teardownEngine()
                    DispatchQueue.main.async {
                        self.partial = ""
                        self.state = .idle
                        self.onUtterance?(text)
                    }
                }
            } else if error != nil {
                self.teardownEngine()
                DispatchQueue.main.async { self.state = .idle }
            }
        }

        try audioEngine.start()
        state = .recording
    }

    func stop() {
        teardownEngine()
        recognitionTask?.cancel()
        recognitionTask = nil
        request?.endAudio()
        request = nil
        partial = ""
        state = .idle
    }

    private func teardownEngine() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }
}
