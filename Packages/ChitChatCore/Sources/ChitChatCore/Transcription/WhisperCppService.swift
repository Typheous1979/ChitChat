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
    private var cachedWhisper: Whisper?
    private var periodicTask: Task<Void, Never>?
    private var isInferring = false
    private var lastPartialSampleCount: Int = 0

    public var state: TranscriptionState {
        lock.withLock { _state }
    }

    public let supportsStreaming = true
    public let engineName = "Whisper (Offline)"

    private let modelPath: String?

    /// Seconds of audio to accumulate before the first partial inference.
    private let minAudioForPartial: Double = 2.0
    /// Seconds between successive partial inferences.
    private let partialInterval: Double = 3.0
    /// Minimum new audio (in seconds) required to justify a new partial inference.
    private let minNewAudioForPartial: Double = 1.0

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

        // Cache the Whisper model instance — loading from disk is expensive.
        // Only reload if the model isn't cached yet.
        if cachedWhisper == nil {
            let modelURL = URL(fileURLWithPath: modelPath)
            Log.transcription.info("Loading Whisper model from \(modelPath, privacy: .public)")
            cachedWhisper = Whisper(fromFileURL: modelURL)
        }

        guard let whisper = cachedWhisper else {
            throw TranscriptionError.modelNotLoaded
        }

        lock.withLock {
            _state = .listening
            audioBuffer = Data()
            isInferring = false
            lastPartialSampleCount = 0
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
            try? await Task.sleep(for: .seconds(self.minAudioForPartial))
            while !Task.isCancelled {
                await self.runInference(isFinal: false)
                try? await Task.sleep(for: .seconds(self.partialInterval))
            }
        }

        Log.transcription.info("Whisper session started (model cached)")
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

        // Wait for any in-flight inference to complete (with timeout)
        var waited: TimeInterval = 0
        let maxWait: TimeInterval = 10.0
        while lock.withLock({ isInferring }) && waited < maxWait {
            try? await Task.sleep(for: .milliseconds(50))
            waited += 0.05
        }
        if waited >= maxWait {
            Log.transcription.error("Whisper inference timed out after \(maxWait)s, forcing completion")
            lock.withLock { isInferring = false }
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
        // Don't nil cachedWhisper — keep it for next session
    }

    /// Strip whisper.cpp non-speech annotation tokens like [MUSIC], [BIRDS CHIRPING], (laughing), etc.
    private static let noisePattern = try! NSRegularExpression(pattern: #"\[.*?\]|\(.*?\)"#)

    private static func stripNoiseTokens(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return noisePattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Invalidate the cached model (e.g. when the user switches models).
    public func invalidateModelCache() {
        cachedWhisper = nil
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

        let audioData = lock.withLock { audioBuffer }
        guard let whisper = cachedWhisper, !audioData.isEmpty else { return }

        // Convert Float32 PCM Data → [Float] for SwiftWhisper
        let totalSamples = audioData.count / MemoryLayout<Float>.size
        guard totalSamples > 0 else { return }

        // For partials, skip if not enough new audio since last partial
        if !isFinal {
            let newSamples = totalSamples - lock.withLock({ lastPartialSampleCount })
            let minNewSamples = Int(minNewAudioForPartial * 16000)
            guard newSamples >= minNewSamples else { return }
        }

        let frames: [Float] = audioData.withUnsafeBytes { raw in
            let bound = raw.bindMemory(to: Float.self)
            return Array(bound)
        }

        lock.withLock { lastPartialSampleCount = totalSamples }

        do {
            let segments = try await whisper.transcribe(audioFrames: frames)
            let rawText = segments.map(\.text).joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip all whisper.cpp non-speech annotations:
            // [BLANK_AUDIO], [MUSIC], [MUSIC PLAYING IN THE BACKGROUND], [BIRDS CHIRPING], etc.
            // (blank audio), (music), (laughing), etc.
            let text = Self.stripNoiseTokens(rawText)

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
