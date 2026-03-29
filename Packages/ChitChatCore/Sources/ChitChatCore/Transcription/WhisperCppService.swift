import Foundation
import SwiftWhisper

/// Offline speech-to-text using whisper.cpp via SwiftWhisper.
/// Loads a GGML model file and runs inference on captured audio.
/// Emits periodic partial results during recording and a final result on finish.
public final class WhisperCppService: TranscriptionService, @unchecked Sendable {
    private let lock = NSLock()
    private var _state: TranscriptionState = .idle
    private var audioBuffer = Data()
    private var resultContinuation: AsyncStream<TranscriptionResult>.Continuation?
    private var whisperInstance: Whisper?
    private var periodicTask: Task<Void, Never>?
    private var isInferring = false

    public var state: TranscriptionState {
        lock.withLock { _state }
    }

    public let supportsStreaming = true
    public let engineName = "Whisper (Offline)"

    private let modelPath: String?

    /// Seconds of audio to accumulate before the first partial inference.
    private let minAudioForPartial: Double = 1.5
    /// Seconds between successive partial inferences.
    private let partialInterval: Double = 2.0

    public init(modelPath: String? = nil) {
        self.modelPath = modelPath
    }

    public var isModelLoaded: Bool {
        guard let modelPath else { return false }
        return FileManager.default.fileExists(atPath: modelPath)
    }

    // MARK: - TranscriptionService

    public func startSession(sampleRate: Int, channels: Int) async throws -> AsyncStream<TranscriptionResult> {
        guard let modelPath, isModelLoaded else {
            throw TranscriptionError.modelNotLoaded
        }

        let modelURL = URL(fileURLWithPath: modelPath)
        Log.transcription.info("Loading Whisper model from \(modelPath, privacy: .public)")
        let whisper = Whisper(fromFileURL: modelURL)

        lock.withLock {
            _state = .listening
            audioBuffer = Data()
            whisperInstance = whisper
            isInferring = false
        }

        let stream = AsyncStream<TranscriptionResult> { continuation in
            self.lock.withLock { self.resultContinuation = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock {
                    self?.resultContinuation = nil
                }
            }
        }

        // Launch periodic partial inference in the background
        periodicTask = Task { [weak self] in
            guard let self else { return }
            // Wait for enough audio to accumulate before first partial
            try? await Task.sleep(for: .seconds(self.minAudioForPartial))
            while !Task.isCancelled {
                await self.runInference(isFinal: false)
                try? await Task.sleep(for: .seconds(self.partialInterval))
            }
        }

        Log.transcription.info("Whisper session started")
        return stream
    }

    public func feedAudio(_ buffer: Data) async {
        lock.withLock { audioBuffer.append(buffer) }
    }

    public func finishAudio() async {
        lock.withLock { _state = .processing }

        // Stop periodic partial inference
        periodicTask?.cancel()
        periodicTask = nil

        // Wait for any in-flight inference to complete
        while lock.withLock({ isInferring }) {
            try? await Task.sleep(for: .milliseconds(50))
        }

        // Run final inference on all accumulated audio
        await runInference(isFinal: true)

        // Close the result stream (extract continuation first to avoid deadlock)
        let continuation: AsyncStream<TranscriptionResult>.Continuation? = lock.withLock {
            let c = resultContinuation
            resultContinuation = nil
            _state = .idle
            return c
        }
        continuation?.finish()
    }

    public func stopSession() async {
        periodicTask?.cancel()
        periodicTask = nil

        let continuation: AsyncStream<TranscriptionResult>.Continuation? = lock.withLock {
            let c = resultContinuation
            resultContinuation = nil
            audioBuffer = Data()
            _state = .idle
            return c
        }
        continuation?.finish()
        whisperInstance = nil
    }

    // MARK: - Inference

    private func runInference(isFinal: Bool) async {
        // Serialize access — only one inference at a time
        let canRun = lock.withLock { () -> Bool in
            guard !isInferring else { return false }
            isInferring = true
            return true
        }
        guard canRun else { return }
        defer { lock.withLock { isInferring = false } }

        let (audioData, whisper) = lock.withLock { (audioBuffer, whisperInstance) }
        guard let whisper, !audioData.isEmpty else { return }

        // Convert Float32 PCM Data → [Float] for SwiftWhisper
        let floatCount = audioData.count / MemoryLayout<Float>.size
        guard floatCount > 0 else { return }

        let frames: [Float] = audioData.withUnsafeBytes { raw in
            let bound = raw.bindMemory(to: Float.self)
            return Array(bound)
        }

        do {
            let segments = try await whisper.transcribe(audioFrames: frames)
            let text = segments.map(\.text).joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else { return }

            let result = TranscriptionResult(
                text: text,
                isFinal: isFinal,
                confidence: 1.0,
                timestamp: Date().timeIntervalSince1970
            )

            lock.withLock { _ = resultContinuation?.yield(result) }

            Log.transcription.info("Whisper \(isFinal ? "final" : "partial", privacy: .public): \"\(text, privacy: .public)\"")
        } catch {
            if !Task.isCancelled {
                Log.transcription.error("Whisper inference error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
