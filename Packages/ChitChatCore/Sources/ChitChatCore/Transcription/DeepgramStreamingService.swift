import Foundation

/// Real-time speech-to-text using Deepgram's Nova-3 streaming API.
public final class DeepgramStreamingService: TranscriptionService, @unchecked Sendable {
    private let apiKey: String
    private let model: String
    private let language: String
    private let lock = NSLock()
    private var webSocket: DeepgramWebSocket?
    private var webSocketTask: URLSessionWebSocketTask?
    private var _state: TranscriptionState = .idle
    private var resultContinuation: AsyncStream<TranscriptionResult>.Continuation?
    private var receiveTask: Task<Void, Never>?

    public var state: TranscriptionState {
        lock.withLock { _state }
    }

    public let supportsStreaming = true
    public var engineName: String { "Deepgram \(model)" }

    public init(apiKey: String, model: String = "nova-3", language: String = "en") {
        self.apiKey = apiKey
        self.model = model
        self.language = language
    }

    public func startSession(sampleRate: Int, channels: Int) async throws -> AsyncStream<TranscriptionResult> {
        guard !apiKey.isEmpty else {
            throw TranscriptionError.apiKeyMissing
        }

        let ws = DeepgramWebSocket(apiKey: apiKey)
        lock.withLock {
            self.webSocket = ws
            self._state = .connecting
        }

        Log.transcription.info("Connecting to Deepgram (model: \(self.model), rate: \(sampleRate)Hz)")

        let task: URLSessionWebSocketTask
        do {
            task = try ws.connect(sampleRate: sampleRate, channels: channels, model: model, language: language)
        } catch {
            Log.transcription.error("Deepgram connection failed: \(error.localizedDescription, privacy: .public)")
            lock.withLock { self._state = .error(.connectionFailed(underlying: error.localizedDescription)) }
            throw TranscriptionError.connectionFailed(underlying: error.localizedDescription)
        }
        Log.transcription.info("Deepgram WebSocket connected")

        lock.withLock {
            self.webSocketTask = task
            self._state = .listening
        }

        return AsyncStream { continuation in
            self.lock.withLock { self.resultContinuation = continuation }

            continuation.onTermination = { [weak self] _ in
                self?.cleanUp()
            }

            self.receiveTask = Task { [weak self] in
                await self?.receiveLoop(task: task, continuation: continuation)
            }
        }
    }

    public func feedAudio(_ buffer: Data) async {
        guard let ws = lock.withLock({ webSocket }) else { return }

        // Convert Float32 PCM to Int16 linear PCM for Deepgram
        let int16Data = AudioFormatConverter.float32ToInt16(buffer)

        do {
            try await ws.sendAudio(int16Data)
        } catch {
            Log.transcription.warning("Failed to send audio buffer: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func finishAudio() async {
        guard let ws = lock.withLock({ webSocket }) else { return }
        lock.withLock { _state = .processing }

        do {
            try await ws.sendCloseStream()
        } catch {
            // Best effort
        }
    }

    public func stopSession() async {
        cleanUp()
    }

    // MARK: - Receive Loop

    private func receiveLoop(task: URLSessionWebSocketTask, continuation: AsyncStream<TranscriptionResult>.Continuation) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    if let result = parseResponse(text) {
                        continuation.yield(result)
                    }
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8),
                       let result = parseResponse(text) {
                        continuation.yield(result)
                    }
                @unknown default:
                    break
                }
            } catch {
                Log.transcription.warning("WebSocket receive error: \(error.localizedDescription, privacy: .public)")
                break
            }
        }

        Log.transcription.info("Deepgram receive loop ended")
        continuation.finish()
        lock.withLock { _state = .idle }
    }

    private func parseResponse(_ json: String) -> TranscriptionResult? {
        guard let data = json.data(using: .utf8),
              let response = try? JSONDecoder().decode(DeepgramResponse.self, from: data) else {
            return nil
        }

        // Skip non-results messages (e.g., metadata, VAD events)
        guard response.type == "Results",
              let channel = response.channel,
              let alternative = channel.alternatives.first else {
            return nil
        }

        let transcript = alternative.transcript
        guard !transcript.isEmpty else { return nil }

        let isFinal = response.isFinal == true || response.speechFinal == true

        let words = alternative.words?.map { word in
            TranscriptionResult.WordTiming(
                word: word.word,
                start: word.start,
                end: word.end,
                confidence: Float(word.confidence)
            )
        }

        return TranscriptionResult(
            text: transcript,
            isFinal: isFinal,
            confidence: Float(alternative.confidence),
            timestamp: Date().timeIntervalSince1970,
            words: words
        )
    }

    // MARK: - Cleanup

    private func cleanUp() {
        receiveTask?.cancel()
        lock.withLock {
            webSocket?.disconnect()
            webSocket = nil
            webSocketTask = nil
            resultContinuation?.finish()
            resultContinuation = nil
            _state = .idle
            receiveTask = nil
        }
    }
}
