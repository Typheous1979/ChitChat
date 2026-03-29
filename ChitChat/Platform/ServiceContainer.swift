import Foundation
import ChitChatCore

@MainActor
final class ServiceContainer {
    let settingsManager: SettingsManager
    let keychain: KeychainHelper
    let audioCaptureService: MacAudioCaptureService
    let accessibilityService: MacAccessibilityService
    let clipboardService: MacClipboardService
    let textInjectionService: MacTextInjectionService
    let hotkeyService: MacHotkeyService
    private(set) var transcriptionCoordinator: TranscriptionCoordinator
    private(set) var dictationOrchestrator: DictationOrchestrator

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        self.keychain = KeychainHelper()
        self.audioCaptureService = MacAudioCaptureService()
        self.accessibilityService = MacAccessibilityService()
        self.clipboardService = MacClipboardService()
        self.textInjectionService = MacTextInjectionService(
            accessibilityService: accessibilityService,
            clipboardService: clipboardService
        )
        self.hotkeyService = MacHotkeyService()

        let deepgramKey = keychain.get("deepgram_api_key")
        let whisperPath = Self.whisperModelPath(for: settingsManager.settings.whisperModel)

        self.transcriptionCoordinator = TranscriptionCoordinator(
            settingsManager: settingsManager,
            deepgramApiKey: deepgramKey,
            whisperModelPath: whisperPath
        )

        // Resolve the active transcription service
        let transcriptionService = transcriptionCoordinator.resolveService()

        // Create the orchestrator with a real or fallback service
        if let service = transcriptionService {
            self.dictationOrchestrator = DictationOrchestrator(
                audioCapture: audioCaptureService,
                transcription: service,
                textInjection: textInjectionService,
                accessibility: accessibilityService,
                clipboard: clipboardService
            )
        } else {
            // No transcription service available — create with a placeholder
            // The user needs to configure an API key or download a model
            self.dictationOrchestrator = DictationOrchestrator(
                audioCapture: audioCaptureService,
                transcription: PlaceholderTranscriptionService(),
                textInjection: textInjectionService,
                accessibility: accessibilityService,
                clipboard: clipboardService
            )
        }
    }

    /// Rebuild the transcription coordinator and orchestrator when settings change
    /// (new API key, engine switch). Call this after saving an API key.
    func rebuildTranscription() {
        let deepgramKey = keychain.get("deepgram_api_key")
        let whisperPath = Self.whisperModelPath(for: settingsManager.settings.whisperModel)

        self.transcriptionCoordinator = TranscriptionCoordinator(
            settingsManager: settingsManager,
            deepgramApiKey: deepgramKey,
            whisperModelPath: whisperPath
        )

        let service = transcriptionCoordinator.resolveService() ?? PlaceholderTranscriptionService()

        self.dictationOrchestrator = DictationOrchestrator(
            audioCapture: audioCaptureService,
            transcription: service,
            textInjection: textInjectionService,
            accessibility: accessibilityService,
            clipboard: clipboardService
        )
    }

    static func whisperModelPath(for model: WhisperModelSize) -> String? {
        let path = WhisperModelManager.modelPath(for: model).path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }
}

// MARK: - Placeholder Service

/// Used when no real transcription service is configured.
/// Yields no results and reports a clear error.
private final class PlaceholderTranscriptionService: TranscriptionService, @unchecked Sendable {
    var state: TranscriptionState { .idle }
    var supportsStreaming: Bool { false }
    var engineName: String { "Not Configured" }

    func startSession(sampleRate: Int, channels: Int) async throws -> AsyncStream<TranscriptionResult> {
        throw TranscriptionError.apiKeyMissing
    }

    func feedAudio(_ buffer: Data) async {}
    func finishAudio() async {}
    func stopSession() async {}
}
