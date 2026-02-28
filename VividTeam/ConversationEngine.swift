// ConversationEngine.swift
// Orchestrates: Mic → MiniMax LLM (streaming SSE) → ElevenLabs TTS (WebSocket).
//
// Usage:
//   let engine = ConversationEngine()
//   engine.start()   // requests permissions, connects, begins listening
//   engine.stop()    // tears everything down
//
// Set your API keys below or inject them via ConversationConfig.

import Foundation
import Observation

// MARK: - Config (fill in your keys)

struct ConversationConfig {
    var minimaxAPIKey:    String
    var elevenLabsAPIKey: String
    var elevenLabsVoiceID: String   // e.g. "21m00Tcm4TlvDq8ikWAM" (Rachel)

    var minimaxModel:     String = "MiniMax-Text-01"
    var systemPrompt:     String = "You are a helpful voice assistant. Be concise and conversational."
}

// MARK: - Engine

@Observable
final class ConversationEngine {

    enum Phase {
        case idle           // not started
        case listening      // mic open, waiting for user to speak
        case thinking       // LLM is generating
        case speaking       // TTS is playing
    }

    // MARK: Observable state

    private(set) var phase: Phase = .idle
    private(set) var agentText: String = ""         // streamed LLM output, current turn
    private(set) var userTranscript: String = ""    // latest user utterance
    private(set) var partialTranscript: String = "" // live mic partial

    // Full conversation history for the LLM
    private(set) var history: [[String: String]] = []

    // MARK: Sub-components

    private let mic: MicrophoneListener
    private let llm: MiniMaxClient
    private let tts: ElevenLabsTTSSocket

    // Characters that signal a sentence boundary → flush TTS for low latency
    private let sentenceBoundaries: Set<Character> = [".", "?", "!", "…", "\n"]

    // MARK: Init

    init(config: ConversationConfig) {
        mic = MicrophoneListener()
        llm = MiniMaxClient(config: MiniMaxConfig(
            apiKey: config.minimaxAPIKey,
            model:  config.minimaxModel,
            systemPrompt: config.systemPrompt
        ))
        tts = ElevenLabsTTSSocket(config: ElevenLabsConfig(
            apiKey:  config.elevenLabsAPIKey,
            voiceID: config.elevenLabsVoiceID
        ))

        // Mirror mic partials into observable property
        mic.onUtterance = { [weak self] text in
            self?.handleUtterance(text)
        }
    }

    // MARK: - Start / Stop

    func start() {
        tts.connect()
        mic.requestPermissions { [weak self] granted in
            guard let self, granted else { return }
            self.startListening()
        }
    }

    func stop() {
        mic.stop()
        llm.cancel()
        tts.disconnect()
        history.removeAll()
        phase = .idle
    }

    // MARK: - Pipeline

    private func startListening() {
        guard phase == .idle || phase == .speaking else { return }
        phase = .listening
        try? mic.start()
    }

    private func handleUtterance(_ text: String) {
        guard !text.isEmpty else {
            startListening()
            return
        }

        // Barge-in: stop TTS if it was speaking
        if phase == .speaking { tts.interrupt() }

        mic.stop()
        userTranscript = text
        phase = .thinking
        agentText = ""

        history.append(["role": "user", "content": text])

        llm.stream(history: history) { [weak self] token in
            guard let self else { return }
            // Already on main thread (MiniMaxClient dispatches to main)
            self.agentText += token
            self.tts.send(token)
            self.phase = .speaking

            // Flush at sentence boundaries so playback starts sooner
            if let last = token.last, self.sentenceBoundaries.contains(last) {
                self.tts.flush()
            }
        } onDone: { [weak self] in
            guard let self else { return }
            self.tts.flush()    // flush remainder
            self.history.append(["role": "assistant", "content": self.agentText])

            // Resume listening after a short pause (let TTS finish draining)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.startListening()
            }
        }
    }
}
