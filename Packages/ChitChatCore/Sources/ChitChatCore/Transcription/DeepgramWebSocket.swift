import Foundation

/// Manages a WebSocket connection to Deepgram's streaming API.
final class DeepgramWebSocket: @unchecked Sendable {
    private let apiKey: String
    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private let lock = NSLock()

    var isConnected: Bool {
        lock.withLock { webSocketTask != nil }
    }

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// Connect to Deepgram streaming endpoint.
    func connect(sampleRate: Int, channels: Int, model: String = "nova-3", language: String = "en") throws -> URLSessionWebSocketTask {
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "endpointing", value: "300"),
            URLQueryItem(name: "vad_events", value: "true"),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "\(sampleRate)"),
            URLQueryItem(name: "channels", value: "\(channels)"),
        ]

        guard let url = components.url else {
            throw TranscriptionError.connectionFailed(underlying: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        lock.withLock { self.webSocketTask = task }
        task.resume()
        return task
    }

    /// Send binary audio data.
    func sendAudio(_ data: Data) async throws {
        guard let task = lock.withLock({ webSocketTask }) else { return }
        try await task.send(.data(data))
    }

    /// Send close stream message to trigger final results.
    func sendCloseStream() async throws {
        guard let task = lock.withLock({ webSocketTask }) else { return }
        let closeMessage = #"{"type": "CloseStream"}"#
        try await task.send(.string(closeMessage))
    }

    /// Disconnect and clean up.
    func disconnect() {
        lock.withLock {
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
        }
    }
}

// MARK: - Deepgram Response Types

struct DeepgramResponse: Codable {
    let type: String
    let channel: Channel?
    let isFinal: Bool?
    let speechFinal: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case channel
        case isFinal = "is_final"
        case speechFinal = "speech_final"
    }

    struct Channel: Codable {
        let alternatives: [Alternative]
    }

    struct Alternative: Codable {
        let transcript: String
        let confidence: Double
        let words: [Word]?
    }

    struct Word: Codable {
        let word: String
        let start: Double
        let end: Double
        let confidence: Double
    }
}
