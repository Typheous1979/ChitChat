import Foundation

/// Protocol for all transcription engine implementations.
/// Engines receive raw PCM audio and produce a stream of transcription results.
public protocol TranscriptionService: AnyObject, Sendable {
    /// Current state of the service.
    var state: TranscriptionState { get }

    /// Start a transcription session. Returns an AsyncStream of results.
    /// Audio buffers are fed via `feedAudio(_:)`.
    func startSession(sampleRate: Int, channels: Int) async throws -> AsyncStream<TranscriptionResult>

    /// Feed raw PCM audio data. Format depends on engine:
    /// - Deepgram: Int16 linear PCM
    /// - Whisper: Float32 PCM
    func feedAudio(_ buffer: Data) async

    /// Signal end of audio input; triggers any final processing.
    func finishAudio() async

    /// Stop the session and clean up resources.
    func stopSession() async

    /// Whether this engine supports real-time streaming (partial results).
    var supportsStreaming: Bool { get }

    /// Human-readable name of the engine.
    var engineName: String { get }
}
