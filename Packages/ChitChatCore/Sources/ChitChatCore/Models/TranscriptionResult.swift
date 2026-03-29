import Foundation

public struct TranscriptionResult: Sendable {
    public let text: String
    public let isFinal: Bool
    public let confidence: Float
    public let timestamp: TimeInterval
    public let words: [WordTiming]?

    public init(text: String, isFinal: Bool, confidence: Float = 1.0, timestamp: TimeInterval = 0, words: [WordTiming]? = nil) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
        self.timestamp = timestamp
        self.words = words
    }

    public struct WordTiming: Sendable {
        public let word: String
        public let start: TimeInterval
        public let end: TimeInterval
        public let confidence: Float

        public init(word: String, start: TimeInterval, end: TimeInterval, confidence: Float = 1.0) {
            self.word = word
            self.start = start
            self.end = end
            self.confidence = confidence
        }
    }
}

public enum TranscriptionState: Sendable {
    case idle
    case connecting
    case listening
    case processing
    case error(TranscriptionError)
}

public enum TranscriptionError: Error, Sendable, LocalizedError {
    case connectionFailed(underlying: String)
    case audioFormatUnsupported
    case apiKeyMissing
    case apiKeyInvalid
    case rateLimited
    case modelNotLoaded
    case cancelled
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let underlying): return "Transcription connection failed: \(underlying)"
        case .audioFormatUnsupported: return "Audio format is not supported by the transcription engine."
        case .apiKeyMissing: return "No API key configured. Open Settings > Transcription to add your Deepgram API key."
        case .apiKeyInvalid: return "API key is invalid. Check your Deepgram API key in Settings > Transcription."
        case .rateLimited: return "Transcription rate limit exceeded. Please wait and try again."
        case .modelNotLoaded: return "Whisper model not downloaded. Open Settings > Transcription to download a model."
        case .cancelled: return "Transcription was cancelled."
        case .unknown(let detail): return "Transcription error: \(detail)"
        }
    }
}
