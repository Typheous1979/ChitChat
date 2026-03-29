import Foundation

public struct VoiceProfile: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var customVocabulary: [String]
    public var corrections: [String: String]
    public var completedPromptIds: [String]
    public var initialPrompt: String
    public var isComplete: Bool

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), customVocabulary: [String] = [], corrections: [String: String] = [:], completedPromptIds: [String] = [], initialPrompt: String = "", isComplete: Bool = false) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.customVocabulary = customVocabulary
        self.corrections = corrections
        self.completedPromptIds = completedPromptIds
        self.initialPrompt = initialPrompt
        self.isComplete = isComplete
    }
}
