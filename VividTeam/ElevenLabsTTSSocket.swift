// ElevenLabsTTSSocket.swift
// Streams TTS audio from ElevenLabs via WebSocket and plays it in real-time.
//
// Protocol:
//   1. connect()              — opens WS + sends BOS message
//   2. send("word by word")  — pipe LLM tokens in as they arrive
//   3. flush()               — signals end of utterance (sends empty text)
//   4. interrupt()           — stops playback for barge-in
//
// Audio format: PCM 22050 Hz → converted to Float32 for AVAudioPlayerNode.

import Foundation
import AVFoundation
import Observation

// MARK: - Config

struct ElevenLabsConfig {
    var apiKey: String
    var voiceID: String         // e.g. "21m00Tcm4TlvDq8ikWAM" (Rachel)
    var modelID: String = "eleven_turbo_v2_5"
    var stability: Double = 0.5
    var similarityBoost: Double = 0.75
}

// MARK: - Socket

@Observable
final class ElevenLabsTTSSocket: NSObject {

    enum State { case disconnected, ready, speaking }
    private(set) var state: State = .disconnected

    private let config: ElevenLabsConfig
    private var socket: URLSessionWebSocketTask?

    // Audio playback
    private let audioEngine = AVAudioEngine()
    private let playerNode  = AVAudioPlayerNode()

    // ElevenLabs PCM: 22050 Hz, Int16, mono — we convert to Float32 for AVAudioEngine
    // `lazy` is incompatible with @Observable (the macro turns stored props into
    // computed ones, which breaks lazy init). Use a plain `let` instead.
    private let playFormat: AVAudioFormat

    // MARK: - Init

    init(config: ElevenLabsConfig) {
        self.config = config
        self.playFormat = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
        super.init()
        setupAudio()
    }

    // MARK: - Audio Setup

    private func setupAudio() {
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playFormat)
        try? audioEngine.start()
    }

    // MARK: - WebSocket Lifecycle

    func connect() {
        guard state == .disconnected else { return }

        let urlStr = "wss://api.elevenlabs.io/v1/text-to-speech/\(config.voiceID)/stream-input"
            + "?model_id=\(config.modelID)"
            + "&output_format=pcm_22050"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.setValue(config.apiKey, forHTTPHeaderField: "xi-api-key")

        let ws = URLSession.shared.webSocketTask(with: req)
        socket = ws
        ws.resume()

        // BOS — voice settings handshake
        sendJSON([
            "text": " ",
            "voice_settings": [
                "stability": config.stability,
                "similarity_boost": config.similarityBoost
            ]
        ])

        state = .ready
        listenLoop()
    }

    func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        state = .disconnected
    }

    // MARK: - Text Input

    /// Send a chunk of text as it arrives from the LLM.
    func send(_ text: String) {
        guard state != .disconnected, !text.isEmpty else { return }
        sendJSON(["text": text, "try_trigger_generation": true])
        state = .speaking
    }

    /// Flush remaining audio at a sentence boundary or end of response.
    func flush() {
        guard state != .disconnected else { return }
        sendJSON(["text": ""])
    }

    // MARK: - Barge-In

    /// Immediately stop playback so the user can interrupt the agent.
    func interrupt() {
        playerNode.stop()
        if !audioEngine.isRunning { try? audioEngine.start() }
        playerNode.play()   // re-arm for next turn
        state = .ready
    }

    // MARK: - Private helpers

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str  = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(str)) { _ in }
    }

    private func listenLoop() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message { self.handleMessage(text) }
                self.listenLoop()   // re-arm
            case .failure:
                DispatchQueue.main.async { self.state = .disconnected }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard
            let data   = text.data(using: .utf8),
            let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let b64    = json["audio"] as? String,
            let pcmData = Data(base64Encoded: b64)
        else { return }

        scheduleAudio(pcmData)

        if (json["isFinal"] as? Bool) == true {
            DispatchQueue.main.async { self.state = .ready }
        }
    }

    // MARK: - PCM → Float32 → schedule

    private func scheduleAudio(_ pcmData: Data) {
        // ElevenLabs sends raw Int16 LE PCM at 22050 Hz mono
        let frameCount = AVAudioFrameCount(pcmData.count / 2)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: frameCount)
        else { return }

        buffer.frameLength = frameCount

        pcmData.withUnsafeBytes { raw in
            guard let src = raw.bindMemory(to: Int16.self).baseAddress,
                  let dst = buffer.floatChannelData?[0] else { return }
            // Normalise Int16 → Float32 in [-1, 1]
            for i in 0..<Int(frameCount) {
                dst[i] = Float(src[i]) / 32_768.0
            }
        }

        playerNode.scheduleBuffer(buffer)
        if !playerNode.isPlaying { playerNode.play() }
    }
}
