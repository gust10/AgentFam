// MiniMaxClient.swift
// Streams chat completions from MiniMax via Server-Sent Events (SSE).
// Uses URLSessionDataDelegate for true incremental delivery.

import Foundation

// MARK: - Config

struct MiniMaxConfig {
    var apiKey: String
    var model: String = "MiniMax-Text-01"
    var systemPrompt: String = "You are a helpful, concise voice assistant. Keep answers brief and conversational."
    var baseURL: String = "https://api.minimax.chat/v1/text/chatcompletion_v2"
}

// MARK: - Client

final class MiniMaxClient {

    private let config: MiniMaxConfig
    private var activeSession: StreamingSession?

    init(config: MiniMaxConfig) {
        self.config = config
    }

    /// Stream a chat response.
    /// - Parameters:
    ///   - history: Array of `["role": "user"/"assistant", "content": "..."]` dicts.
    ///   - onToken: Called on main thread for each text delta.
    ///   - onDone:  Called on main thread when the stream ends.
    func stream(
        history: [[String: String]],
        onToken: @escaping (String) -> Void,
        onDone: @escaping () -> Void
    ) {
        activeSession = nil  // cancels any in-flight request

        var messages: [[String: String]] = [
            ["role": "system", "content": config.systemPrompt]
        ]
        messages += history

        var req = URLRequest(url: URL(string: config.baseURL)!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": config.model,
            "stream": true,
            "messages": messages
        ])

        let parser = SSEParser(onToken: onToken, onDone: onDone)
        let session = StreamingSession(
            onData: { parser.consume($0) },
            onComplete: { DispatchQueue.main.async { onDone() } }
        )
        activeSession = session
        session.start(req)
    }

    func cancel() {
        activeSession = nil
    }
}

// MARK: - SSE Line Parser

private final class SSEParser {
    private var buffer = Data()
    private var didCallDone = false
    private let onToken: (String) -> Void
    private let onDone: () -> Void

    init(onToken: @escaping (String) -> Void, onDone: @escaping () -> Void) {
        self.onToken = onToken
        self.onDone = onDone
    }

    func consume(_ data: Data) {
        buffer.append(data)

        // Process complete lines (delimited by \n)
        while let newlineRange = buffer.range(of: Data("\n".utf8)) {
            let lineData = buffer[buffer.startIndex..<newlineRange.lowerBound]
            buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)

            guard
                let line = String(data: lineData, encoding: .utf8),
                line.hasPrefix("data: ")
            else { continue }

            let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)

            if payload == "[DONE]" {
                callDoneOnce()
                return
            }

            guard
                let jsonData = payload.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]],
                let delta = choices.first?["delta"] as? [String: Any],
                let content = delta["content"] as? String,
                !content.isEmpty
            else { continue }

            DispatchQueue.main.async { self.onToken(content) }
        }
    }

    private func callDoneOnce() {
        guard !didCallDone else { return }
        didCallDone = true
        DispatchQueue.main.async { self.onDone() }
    }
}

// MARK: - Streaming URLSession (incremental delivery via delegate)

private final class StreamingSession: NSObject, URLSessionDataDelegate {
    private let onData: (Data) -> Void
    private let onComplete: () -> Void
    private var task: URLSessionDataTask?

    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()

    init(onData: @escaping (Data) -> Void, onComplete: @escaping () -> Void) {
        self.onData = onData
        self.onComplete = onComplete
    }

    func start(_ request: URLRequest) {
        task = session.dataTask(with: request)
        task?.resume()
    }

    deinit { task?.cancel() }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        onData(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error == nil { onComplete() }
    }
}
