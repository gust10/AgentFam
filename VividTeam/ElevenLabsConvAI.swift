// ElevenLabsConvAI.swift
// Full-duplex voice conversation via ElevenLabs Conversational AI WebSocket.
//
// Agent provisioning:
//   On first start(), if no agentID is cached in UserDefaults, a default agent
//   is created automatically via the ElevenLabs REST API. The resulting ID is
//   saved to UserDefaults so creation only happens once.
//
// Pipeline (single WebSocket handles everything):
//   Mic → PCM 16 kHz base64 chunks → ElevenLabs (VAD + STT + LLM + TTS) → PCM audio out

import Foundation
import AVFoundation
import Observation

// MARK: - Message model

struct ConvAIMessage: Identifiable {
    enum Role { case user, agent }
    let id    = UUID()
    let role:   Role
    let text:   String
}

// MARK: - Config

struct ElevenLabsConvAIConfig {
    var apiKey: String
    var agentID: String? = nil  // nil = auto-create on first run
}

// MARK: - Errors

enum ConvAIError: Error {
    case agentCreationFailed(String)
}

// MARK: - Main class

@Observable
final class ElevenLabsConvAI: NSObject {

    enum State { case idle, provisioning, connecting, listening, agentSpeaking }

    private(set) var state:    State  = .idle
    private(set) var agentText: String = ""
    private(set) var userText:  String = ""
    private(set) var messages: [ConvAIMessage] = []

    private let config: ElevenLabsConvAIConfig
    private var socket: URLSessionWebSocketTask?

    // ── Mic capture ──────────────────────────────────────────────────────────
    private let captureEngine   = AVAudioEngine()
    private let elevenLabsInFmt = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!

    // ── Audio playback ────────────────────────────────────────────────────────
    private let playEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let playFormat = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!

    // MARK: - Init

    init(config: ElevenLabsConvAIConfig) {
        self.config = config
        super.init()
        setupPlayback()
    }

    // MARK: - Public interface

    func start() {
        guard state == .idle else { return }
        state = .provisioning

        Task {
            do {
                let agentID = try await resolveAgentID()
                await MainActor.run { self.openWebSocket(agentID: agentID) }
            } catch {
                print("ConvAI: provisioning failed —", error)
                await MainActor.run { self.state = .idle }
            }
        }
    }

    func stop() {
        stopCapture()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        playerNode.stop()
        state     = .idle
        agentText = ""
        userText  = ""
        messages  = []
    }

    // MARK: - Agent provisioning

    private static let userDefaultsKey = "convai_agent_id"

    private func resolveAgentID() async throws -> String {
        // 1. Cached from a previous run
        if let saved = UserDefaults.standard.string(forKey: Self.userDefaultsKey), !saved.isEmpty {
            return saved
        }
        // 2. Explicitly provided in config
        if let explicit = config.agentID, !explicit.isEmpty {
            return explicit
        }
        // 3. Create a new default agent via API
        let id = try await createDefaultAgent()
        UserDefaults.standard.set(id, forKey: Self.userDefaultsKey)
        print("ConvAI: agent created and cached —", id)
        return id
    }

    private func createDefaultAgent() async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/convai/agents/create")!)
        req.httpMethod = "POST"
        req.setValue(config.apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")

        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": "VividTeam Assistant",
            "conversation_config": [
                "agent": [
                    "prompt": [
                        "prompt": "You are a helpful, concise voice assistant.",
                        "llm": "gpt-4o-mini",
                        "temperature": 1
                    ],
                    "first_message": "Hi! How can I help you?",
                    "language": "en"
                ],
                "asr": [
                    "quality": "high",
                    "provider": "elevenlabs",
                    "user_input_audio_format": "pcm_16000"
                ],
                "tts": [
                    "model_id": "eleven_turbo_v2",
                    "voice_id": "21m00Tcm4TlvDq8ikWAM",
                    "agent_output_audio_format": "pcm_16000"
                ]
            ]
        ])

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ConvAIError.agentCreationFailed("HTTP \(http.statusCode): \(body)")
        }

        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let agentID = json["agent_id"] as? String
        else {
            throw ConvAIError.agentCreationFailed("unexpected response: \(String(data: data, encoding: .utf8) ?? "")")
        }

        return agentID
    }

    // MARK: - WebSocket

    private func openWebSocket(agentID: String) {
        state = .connecting
        let urlStr = "wss://api.elevenlabs.io/v1/convai/conversation"
            + "?agent_id=\(agentID)"
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
                self.receiveLoop()
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
            DispatchQueue.main.async {
                self.state = .listening
                self.startCapture()
            }

        case "ping":
            if let evt = json["ping_event"] as? [String: Any],
               let id  = evt["event_id"] as? Int {
                sendJSON(["type": "pong", "event_id": id])
            }

        case "audio":
            if let evt = json["audio_event"] as? [String: Any],
               let b64 = evt["audio_base_64"] as? String,
               let pcm = Data(base64Encoded: b64) {
                DispatchQueue.main.async { self.state = .agentSpeaking }
                schedulePlayback(pcm)
            }

        case "agent_response":
            if let evt  = json["agent_response_event"] as? [String: Any],
               let resp = evt["agent_response"] as? String, !resp.isEmpty {
                DispatchQueue.main.async {
                    self.agentText = resp
                    self.messages.append(ConvAIMessage(role: .agent, text: resp))
                }
            }

        case "user_transcript":
            if let evt = json["user_transcription_event"] as? [String: Any],
               let trs = evt["user_transcript"] as? String, !trs.isEmpty {
                DispatchQueue.main.async {
                    self.userText = trs
                    self.messages.append(ConvAIMessage(role: .user, text: trs))
                }
            }

        case "interruption":
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
        let inputNode = captureEngine.inputNode
        let nativeFmt = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: nativeFmt, to: elevenLabsInFmt) else {
            print("ConvAI: could not create audio converter"); return
        }

        let tapSize = AVAudioFrameCount(nativeFmt.sampleRate * 0.02)  // 20 ms chunks
        inputNode.installTap(onBus: 0, bufferSize: tapSize, format: nativeFmt) { [weak self] buf, _ in
            self?.convertAndSend(buf, converter: converter)
        }

        do    { try captureEngine.start() }
        catch { print("ConvAI: mic engine failed:", error) }
    }

    private func stopCapture() {
        captureEngine.inputNode.removeTap(onBus: 0)
        captureEngine.stop()
    }

    private func convertAndSend(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        let ratio    = elevenLabsInFmt.sampleRate / buffer.format.sampleRate
        let outCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: elevenLabsInFmt, frameCapacity: outCount) else { return }

        var consumed = false
        var err: NSError?
        converter.convert(to: outBuf, error: &err) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true; status.pointee = .haveData; return buffer
        }

        guard err == nil, outBuf.frameLength > 0,
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
        let frameCount = AVAudioFrameCount(pcmData.count / 2)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: frameCount)
        else { return }

        buffer.frameLength = frameCount
        pcmData.withUnsafeBytes { raw in
            guard let src = raw.bindMemory(to: Int16.self).baseAddress,
                  let dst = buffer.floatChannelData?[0] else { return }
            for i in 0..<Int(frameCount) { dst[i] = Float(src[i]) / 32_768.0 }
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
