import Foundation

public enum HotkeyEvent: Sendable {
    case pressed
    case released
}

/// Protocol for global hotkey registration and events.
public protocol HotkeyService: AnyObject, Sendable {
    /// Register a global hotkey. Returns a stream of press/release events.
    func register(binding: HotkeyBinding) async throws -> AsyncStream<HotkeyEvent>

    /// Unregister the current hotkey.
    func unregister() async

    /// Current registered binding.
    var currentBinding: HotkeyBinding? { get }

    /// Whether global hotkey permissions are available.
    func checkPermissions() async -> Bool
}
