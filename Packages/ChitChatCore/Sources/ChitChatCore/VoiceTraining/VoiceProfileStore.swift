import Foundation

/// File-based storage for voice profiles in ~/Library/Application Support/ChitChat/VoiceProfiles/.
public final class VoiceProfileStore: Sendable {
    private let baseDirectory: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.baseDirectory = appSupport.appendingPathComponent("ChitChat/VoiceProfiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    /// For testing with a custom directory.
    public init(directory: URL) {
        self.baseDirectory = directory
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    // MARK: - CRUD

    public func listProfiles() throws -> [VoiceProfile] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil
        )
        return contents
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> VoiceProfile? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(VoiceProfile.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func loadProfile(id: UUID) throws -> VoiceProfile? {
        let url = profileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(VoiceProfile.self, from: data)
    }

    public func saveProfile(_ profile: VoiceProfile) throws {
        let data = try JSONEncoder().encode(profile)
        try data.write(to: profileURL(for: profile.id))
    }

    public func deleteProfile(id: UUID) throws {
        let url = profileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        // Also remove recordings directory
        let recordingsDir = recordingsDirectory(for: id)
        if FileManager.default.fileExists(atPath: recordingsDir.path) {
            try FileManager.default.removeItem(at: recordingsDir)
        }
    }

    // MARK: - Recording Storage

    public func recordingsDirectory(for profileId: UUID) -> URL {
        let dir = baseDirectory.appendingPathComponent("\(profileId.uuidString)/recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func saveRecording(profileId: UUID, promptId: String, audioData: Data) throws -> URL {
        let dir = recordingsDirectory(for: profileId)
        let filename = "\(promptId)_\(Int(Date().timeIntervalSince1970)).wav"
        let url = dir.appendingPathComponent(filename)
        try audioData.write(to: url)
        return url
    }

    // MARK: - Helpers

    private func profileURL(for id: UUID) -> URL {
        baseDirectory.appendingPathComponent("\(id.uuidString).json")
    }
}
