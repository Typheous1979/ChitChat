import Foundation
import Testing
@testable import ChitChatCore

@Suite("TranscriptionCoordinator Tests")
struct TranscriptionCoordinatorTests {
    @Test("Resolves Deepgram when API key provided")
    func resolvesDeepgram() {
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.update { $0.transcriptionEngine = .deepgram }

        let coordinator = TranscriptionCoordinator(
            settingsManager: settings,
            deepgramApiKey: "test-key",
            whisperModelPath: nil
        )

        let service = coordinator.resolveService()
        #expect(service != nil)
        #expect(service?.engineName == "Deepgram Nova-3")
        #expect(coordinator.activeEngine == .deepgram)
    }

    @Test("Returns nil when no services available")
    func noServicesAvailable() {
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.update { $0.transcriptionEngine = .deepgram }

        let coordinator = TranscriptionCoordinator(
            settingsManager: settings,
            deepgramApiKey: nil,
            whisperModelPath: nil
        )

        let service = coordinator.resolveService()
        #expect(service == nil)
    }

    @Test("Falls back from Whisper to Deepgram when model not downloaded")
    func fallsBackToDeepgram() {
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.update { $0.transcriptionEngine = .whisperCpp }

        let coordinator = TranscriptionCoordinator(
            settingsManager: settings,
            deepgramApiKey: "test-key",
            whisperModelPath: "/nonexistent/path/model.bin"
        )

        let service = coordinator.resolveService()
        #expect(service != nil)
        #expect(coordinator.activeEngine == .deepgram) // Fell back
        #expect(service?.engineName == "Deepgram Nova-3")
    }

    @Test("Whisper model availability check")
    func whisperAvailability() {
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)

        let coordinator = TranscriptionCoordinator(
            settingsManager: settings,
            deepgramApiKey: nil,
            whisperModelPath: "/nonexistent/model.bin"
        )

        #expect(!coordinator.isWhisperModelAvailable)
    }
}
