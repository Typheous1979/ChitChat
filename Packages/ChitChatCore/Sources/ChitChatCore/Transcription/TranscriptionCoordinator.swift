import Foundation

/// Coordinates transcription engine selection, switching, and fallback.
/// Provides a single interface to the DictationOrchestrator regardless of which engine is active.
@Observable
public final class TranscriptionCoordinator: @unchecked Sendable {
    private let deepgramService: DeepgramStreamingService?
    private let whisperService: WhisperCppService?
    private let settingsManager: SettingsManager
    private let lock = NSLock()

    public private(set) var activeEngine: TranscriptionEngine
    public private(set) var activeService: (any TranscriptionService)?

    public init(settingsManager: SettingsManager, deepgramApiKey: String?, whisperModelPath: String?) {
        self.settingsManager = settingsManager
        self.activeEngine = settingsManager.settings.transcriptionEngine

        if let apiKey = deepgramApiKey, !apiKey.isEmpty {
            self.deepgramService = DeepgramStreamingService(
                apiKey: apiKey,
                model: settingsManager.settings.deepgramModel,
                language: settingsManager.settings.deepgramLanguage
            )
        } else {
            self.deepgramService = nil
        }

        if let modelPath = whisperModelPath {
            self.whisperService = WhisperCppService(modelPath: modelPath)
        } else {
            self.whisperService = nil
        }

        self.activeService = selectService(for: activeEngine)
    }

    /// Get the currently active transcription service.
    /// Falls back to the other engine if the preferred one is unavailable.
    public func resolveService() -> (any TranscriptionService)? {
        if let service = selectService(for: settingsManager.settings.transcriptionEngine) {
            activeEngine = settingsManager.settings.transcriptionEngine
            activeService = service
            return service
        }

        // Fallback: try the other engine
        let fallback: TranscriptionEngine = settingsManager.settings.transcriptionEngine == .deepgram ? .whisperCpp : .deepgram
        if let service = selectService(for: fallback) {
            activeEngine = fallback
            activeService = service
            return service
        }

        return nil
    }

    /// Explicitly switch to a different engine, stopping the previous one.
    public func switchEngine(to engine: TranscriptionEngine) async -> (any TranscriptionService)? {
        await activeService?.stopSession()
        activeEngine = engine
        activeService = selectService(for: engine)
        return activeService
    }

    /// Test if Deepgram connection works with the current API key.
    public func testDeepgramConnection() async -> Result<String, TranscriptionError> {
        guard let service = deepgramService else {
            return .failure(.apiKeyMissing)
        }

        do {
            let stream = try await service.startSession(sampleRate: 16000, channels: 1)
            // Send a tiny silence buffer to verify the connection
            let silence = Data(count: 3200) // 100ms of 16kHz Int16
            await service.feedAudio(silence)

            // Wait briefly for a response
            try await Task.sleep(for: .milliseconds(500))
            await service.stopSession()

            // If we got here without throwing, connection works
            _ = stream // consume to avoid warning
            return .success("Connected to Deepgram Nova-3")
        } catch let error as TranscriptionError {
            return .failure(error)
        } catch {
            return .failure(.connectionFailed(underlying: error.localizedDescription))
        }
    }

    /// Check if Whisper model is available.
    public var isWhisperModelAvailable: Bool {
        whisperService?.isModelLoaded ?? false
    }

    private func selectService(for engine: TranscriptionEngine) -> (any TranscriptionService)? {
        switch engine {
        case .deepgram:
            return deepgramService
        case .whisperCpp:
            guard let whisper = whisperService, whisper.isModelLoaded else { return nil }
            return whisper
        }
    }
}
