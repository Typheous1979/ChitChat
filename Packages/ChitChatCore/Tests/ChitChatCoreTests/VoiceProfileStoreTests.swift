import Foundation
import Testing
@testable import ChitChatCore

@Suite("VoiceProfileStore Tests")
struct VoiceProfileStoreTests {
    private func makeTempStore() -> (VoiceProfileStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chitchat-test-\(UUID().uuidString)")
        let store = VoiceProfileStore(directory: dir)
        return (store, dir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Save and load a profile")
    func saveAndLoad() throws {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let profile = VoiceProfile(name: "Test")
        try store.saveProfile(profile)

        let loaded = try store.loadProfile(id: profile.id)
        #expect(loaded != nil)
        #expect(loaded?.name == "Test")
        #expect(loaded?.id == profile.id)
    }

    @Test("List profiles returns all saved profiles")
    func listProfiles() throws {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        try store.saveProfile(VoiceProfile(name: "Profile A"))
        try store.saveProfile(VoiceProfile(name: "Profile B"))

        let profiles = try store.listProfiles()
        #expect(profiles.count == 2)
    }

    @Test("Delete profile removes it")
    func deleteProfile() throws {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let profile = VoiceProfile(name: "ToDelete")
        try store.saveProfile(profile)
        #expect(try store.listProfiles().count == 1)

        try store.deleteProfile(id: profile.id)
        #expect(try store.listProfiles().count == 0)
        #expect(try store.loadProfile(id: profile.id) == nil)
    }

    @Test("Save recording creates file")
    func saveRecording() throws {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let profile = VoiceProfile(name: "RecTest")
        try store.saveProfile(profile)

        let audioData = Data(repeating: 0, count: 1024)
        let url = try store.saveRecording(profileId: profile.id, promptId: "test_1", audioData: audioData)

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: url).count == 1024)
    }
}
