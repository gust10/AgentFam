// ElevenLabsConvAI.swift
// Full-duplex voice conversation via ElevenLabs Conversational AI WebSocket.
//
// This handles the ENTIRE pipeline in one WebSocket connection:
//   Mic → base64 PCM chunks → ElevenLabs ConvAI ←→ (STT + LLM + TTS) → audio out
//
// Setup:
//   1. Create an agent at elevenlabs.io/app/conversational-ai
//   2. Copy the Agent ID
//   3. Instantiate and call start()
//
// Required: microphone permission (NSMicrophoneUsageDescription in Info.plist)

import Foundation
import AVFoundation
import Observation

// MARK: - Config

struct ElevenLabsConvAIConfig {
    var apiKey: String
    var agentID: String
}

// MARK: - Main class

@Observable
final class ElevenLabsConvAI: NSObject {

    enum State { case idle, connecting, listening, agentSpeaking }

    private(set) var state: State = .idle
    private(set) var agentText: String = ""
    private(set) var userText:  String = ""

    private let config: ElevenLabsConvAIConfig
    private var socket: URLSessionWebSocketTask?

    // ── Mic capture ──────────────────────────────────────────────────────────
    private let captureEngine   = AVAudioEngine()
    // ElevenLabs expects PCM 16 kHz, 16-bit, mono
    private let elevenLabsInFmt = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!

    // ── Audio playback ────────────────────────────────────────────────────────
    private let playEngine  = AVAudioEngine()
    private let playerNode  = AVAudioPlayerNode()
    // ConvAI returns PCM 16 kHz by default (we request it in the URL)
    private let playFormat  = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!

    // MARK: - Init

    init(config: ElevenLabsConvAIConfig) {
        self.config = config
        super.init()
        setupPlayback()
    }

    // MARK: - Public interface

    func start() {
        guard state == .idle else { return }
        state = .connecting
        openWebSocket()
    }

    func stop() {
        stopCapture()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        playerNode.stop()
        state = .idle
        agentText = ""
        userText  = ""
    }

    // MARK: - WebSocket

    private func openWebSocket() {
        // Request PCM 16 kHz output so we can play it directly
        let urlStr = "wss://api.elevenlabs.io/v1/convai/conversation"
            + "?agent_id=\(config.agentID)"
            + "&output_format=pcm_16000"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.setValue(config.apiKey, forHTTPHeaderField: "xi-api-key")

        let ws = URLSession.shared.webSocketTask(with: req)
        socket = ws
        ws.resume()
        receiveLoop()
    }

    private func receiveLoop() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message { self.handleMessage(text) }
                self.receiveLoop()   // re-arm
            case .failure(let err):
                print("ConvAI WS error:", err.localizedDescription)
                DispatchQueue.main.async { self.state = .idle }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else { return }

        switch type {

        case "conversation_initiation_metadata":
            // Server handshake complete — start sending mic audio
            DispatchQueue.main.async {
                self.state = .listening
                self.startCapture()
            }

        case "ping":
            // Must pong back or the server drops the connection
            if let evt = json["ping_event"] as? [String: Any],
               let id  = evt["event_id"] as? Int {
                sendJSON(["type": "pong", "event_id": id])
            }

        case "audio":
            if let evt  = json["audio_event"] as? [String: Any],
               let b64  = evt["audio_base_64"] as? String,
               let pcm  = Data(base64Encoded: b64) {
                DispatchQueue.main.async { self.state = .agentSpeaking }
                schedulePlayback(pcm)
            }

        case "agent_response":
            if let evt  = json["agent_response_event"] as? [String: Any],
               let resp = evt["agent_response"] as? String {
                DispatchQueue.main.async { self.agentText = resp }
            }

        case "user_transcript":
            if let evt  = json["user_transcription_event"] as? [String: Any],
               let trs  = evt["user_transcript"] as? String {
                DispatchQueue.main.async { self.userText = trs }
            }

        case "interruption":
            // User started speaking — ElevenLabs already handles VAD; we just stop audio
            DispatchQueue.main.async {
                self.playerNode.stop()
                if self.playEngine.isRunning { self.playerNode.play() }
                self.state = .listening
            }

        default:
            break
        }
    }

    // MARK: - Mic → WebSocket

    private func startCapture() {
        let inputNode   = captureEngine.inputNode
        let nativeFmt   = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: nativeFmt, to: elevenLabsInFmt) else {
            print("ConvAI: could not create audio converter")
            return
        }

        // Buffer ~20 ms of audio per chunk (good latency/overhead balance)
        let tapBufferSize = AVAudioFrameCount(nativeFmt.sampleRate * 0.02)

        inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: nativeFmt) { [weak self] buf, _ in
            self?.convertAndSend(buf, converter: converter)
        }

        do {
            try captureEngine.start()
        } catch {
            print("ConvAI: mic engine failed to start:", error)
        }
    }

    private func stopCapture() {
        captureEngine.inputNode.removeTap(onBus: 0)
        captureEngine.stop()
    }

    private func convertAndSend(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        let ratio         = elevenLabsInFmt.sampleRate / buffer.format.sampleRate
        let outFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outBuf  = AVAudioPCMBuffer(pcmFormat: elevenLabsInFmt, frameCapacity: outFrameCount) else { return }

        var inputConsumed = false
        var convError: NSError?

        converter.convert(to: outBuf, error: &convError) { _, outStatus in
            if inputConsumed { outStatus.pointee = .noDataNow; return nil }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard convError == nil, outBuf.frameLength > 0,
              let samples = outBuf.int16ChannelData?[0] else { return }

        let pcmData = Data(bytes: samples, count: Int(outBuf.frameLength) * 2)
        sendJSON(["user_audio_chunk": pcmData.base64EncodedString()])
    }

    // MARK: - Playback

    private func setupPlayback() {
        playEngine.attach(playerNode)
        playEngine.connect(playerNode, to: playEngine.mainMixerNode, format: playFormat)
        try? playEngine.start()
    }

    private func schedulePlayback(_ pcmData: Data) {
        // Convert Int16 PCM → Float32 for AVAudioPlayerNode
        let frameCount = AVAudioFrameCount(pcmData.count / 2)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: frameCount)
        else { return }

        buffer.frameLength = frameCount

        pcmData.withUnsafeBytes { raw in
            guard let src = raw.bindMemory(to: Int16.self).baseAddress,
                  let dst = buffer.floatChannelData?[0] else { return }
            for i in 0..<Int(frameCount) {
                dst[i] = Float(src[i]) / 32_768.0
            }
        }

        playerNode.scheduleBuffer(buffer)
        if !playerNode.isPlaying { playerNode.play() }
    }

    // MARK: - Helpers

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str  = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(str)) { _ in }
    }
}
