import Foundation

public struct ClipboardEntry: Identifiable, Sendable, Codable {
    public let id: UUID
    public let text: String
    public let timestamp: Date
    public let source: String

    public init(id: UUID = UUID(), text: String, timestamp: Date = Date(), source: String) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.source = source
    }
}

/// Protocol for internal clipboard management.
public protocol ClipboardService: AnyObject, Sendable {
    /// Store text in internal clipboard.
    func store(text: String, source: String) async

    /// Get recent entries.
    func recentEntries(limit: Int) async -> [ClipboardEntry]

    /// Copy a specific entry to the system clipboard.
    func copyToSystemClipboard(entry: ClipboardEntry) async

    /// Clear all entries.
    func clearAll() async
}
