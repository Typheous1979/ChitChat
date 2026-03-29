import Foundation
import Testing
@testable import ChitChatCore

@Suite("VoiceTrainingManager Tests")
struct VoiceTrainingManagerTests {
    private func makeTempManager() -> (VoiceTrainingManager, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chitchat-training-\(UUID().uuidString)")
        let store = VoiceProfileStore(directory: dir)
        let manager = VoiceTrainingManager(profileStore: store)
        return (manager, dir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Create profile and check initial state")
    func createProfile() throws {
        let (manager, dir) = makeTempManager()
        defer { cleanup(dir) }

        let profile = try manager.createProfile(name: "Test User")
        #expect(profile.name == "Test User")
        #expect(profile.completedPromptIds.isEmpty)
        #expect(!profile.isComplete)
        #expect(manager.trainingProgress == 0)
        #expect(manager.currentProfile?.id == profile.id)
    }

    @Test("Next prompt returns first uncompleted prompt")
    func nextPrompt() throws {
        let (manager, dir) = makeTempManager()
        defer { cleanup(dir) }

        _ = try manager.createProfile(name: "Test")

        let first = manager.nextTrainingPrompt()
        #expect(first != nil)
        #expect(first?.id == TrainingPrompts.all.first?.id)
    }

    @Test("Recording a sample updates progress")
    func recordSample() throws {
        let (manager, dir) = makeTempManager()
        defer { cleanup(dir) }

        _ = try manager.createProfile(name: "Test")
        let prompt = TrainingPrompts.all[0]

        try manager.recordTrainingSample(
            promptId: prompt.id,
            expectedText: prompt.text,
            transcribedText: prompt.text, // Perfect transcription
            audioData: Data(repeating: 0, count: 512)
        )

        #expect(manager.trainingProgress > 0)
        #expect(manager.currentProfile?.completedPromptIds.count == 1)
    }

    @Test("Corrections are learned from mismatches")
    func learnCorrections() throws {
        let (manager, dir) = makeTempManager()
        defer { cleanup(dir) }

        _ = try manager.createProfile(name: "Test")

        try manager.recordTrainingSample(
            promptId: "test",
            expectedText: "Hello Justin how are you",
            transcribedText: "Hello Dustin how are you",
            audioData: Data(repeating: 0, count: 512)
        )

        // "dustin" -> "justin" should be learned
        #expect(manager.currentProfile?.corrections["dustin"] == "justin")
    }

    @Test("Load profiles lists saved profiles")
    func loadProfiles() throws {
        let (manager, dir) = makeTempManager()
        defer { cleanup(dir) }

        _ = try manager.createProfile(name: "Profile 1")
        _ = try manager.createProfile(name: "Profile 2")

        let profiles = manager.loadProfiles()
        #expect(profiles.count == 2)
    }
}
