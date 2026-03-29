import Foundation

/// Protocol for voice profile management and training.
public protocol VoiceProfileService: AnyObject, Sendable {
    /// List all saved voice profiles.
    func listProfiles() async -> [VoiceProfile]

    /// Get the active profile.
    func activeProfile() async -> VoiceProfile?

    /// Create a new voice profile.
    func createProfile(name: String) async throws -> VoiceProfile

    /// Delete a voice profile.
    func deleteProfile(id: UUID) async throws

    /// Set a profile as active.
    func setActiveProfile(id: UUID) async throws
}
