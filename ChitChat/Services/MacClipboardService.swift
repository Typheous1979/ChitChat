import AppKit
import ChitChatCore

/// Internal clipboard for storing transcriptions when no text field is focused.
/// Also provides system clipboard save/restore for paste-based injection.
final class MacClipboardService: ClipboardService, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [ClipboardEntry] = []
    private let maxEntries = 50

    // MARK: - ClipboardService

    func store(text: String, source: String) async {
        let entry = ClipboardEntry(text: text, source: source)
        lock.withLock {
            entries.insert(entry, at: 0)
            if entries.count > maxEntries {
                entries.removeLast()
            }
        }

        // Also copy to system clipboard for convenience
        await copyToSystemClipboard(entry: entry)
    }

    func recentEntries(limit: Int) async -> [ClipboardEntry] {
        lock.withLock {
            Array(entries.prefix(limit))
        }
    }

    func copyToSystemClipboard(entry: ClipboardEntry) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
    }

    func clearAll() async {
        lock.withLock { entries.removeAll() }
    }

    // MARK: - System Clipboard Save/Restore

    /// Save current system clipboard contents so they can be restored after paste injection.
    func saveSystemClipboard() -> [NSPasteboard.PasteboardType: Data]? {
        let pasteboard = NSPasteboard.general
        guard let types = pasteboard.types else { return nil }

        var saved: [NSPasteboard.PasteboardType: Data] = [:]
        for type in types {
            if let data = pasteboard.data(forType: type) {
                saved[type] = data
            }
        }
        return saved.isEmpty ? nil : saved
    }

    /// Restore previously saved clipboard contents.
    func restoreSystemClipboard(from saved: [NSPasteboard.PasteboardType: Data]?) {
        guard let saved, !saved.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for (type, data) in saved {
            pasteboard.setData(data, forType: type)
        }
    }
}
