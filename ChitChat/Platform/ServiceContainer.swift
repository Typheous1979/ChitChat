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
                clipboard: clipboardService,
                settingsManager: settingsManager
            )
        } else {
            // No transcription service available — create with a placeholder
            // The user needs to configure an API key or download a model
            self.dictationOrchestrator = DictationOrchestrator(
                audioCapture: audioCaptureService,
                transcription: PlaceholderTranscriptionService(),
                textInjection: textInjectionService,
                accessibility: accessibilityService,
                clipboard: clipboardService,
                settingsManager: settingsManager
            )
        }

        applyVoiceProfilePrompt()
    }

    /// Rebuild the transcription coordinator and orchestrator when settings change
    /// (new API key, engine switch). Call this after saving an API key.
    func rebuildTranscription() {
        guard !dictationOrchestrator.isActive else {
            Log.orchestrator.warning("Cannot rebuild transcription while dictation is active")
            return
        }

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
            clipboard: clipboardService,
            settingsManager: settingsManager
        )

        applyVoiceProfilePrompt()
    }

    static func whisperModelPath(for model: WhisperModelSize) -> String? {
        let path = WhisperModelManager.modelPath(for: model).path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    /// Load the active voice profile's initial prompt and apply to Whisper.
    private func applyVoiceProfilePrompt() {
        guard let profileId = settingsManager.settings.activeVoiceProfileId else { return }
        let store = VoiceProfileStore()
        guard let profile = try? store.loadProfile(id: profileId),
              profile.isComplete, !profile.initialPrompt.isEmpty else { return }
        transcriptionCoordinator.setWhisperInitialPrompt(profile.initialPrompt)
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
