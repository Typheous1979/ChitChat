import Foundation

public enum TextInjectionTarget: Sendable {
    case focusedTextField
    case internalClipboard
}

public struct InjectionResult: Sendable {
    public let target: TextInjectionTarget
    public let injectedText: String
    public let success: Bool
    public let fallbackReason: String?

    public init(target: TextInjectionTarget, injectedText: String, success: Bool, fallbackReason: String? = nil) {
        self.target = target
        self.injectedText = injectedText
        self.success = success
        self.fallbackReason = fallbackReason
    }
}

/// Protocol for injecting transcribed text into the focused application.
public protocol TextInjectionService: AnyObject, Sendable {
    /// Inject text into the currently focused application.
    func injectText(_ text: String) async -> InjectionResult

    /// Inject text incrementally, replacing the last N characters of previous partial.
    func injectIncremental(newText: String, replacingLast characterCount: Int) async -> InjectionResult

    /// Whether incremental injection is supported for the current target.
    var supportsIncrementalInjection: Bool { get }

    /// Check if we have the necessary permissions.
    func checkPermissions() async -> Bool

    /// Request/prompt for necessary permissions.
    func requestPermissions() async
}
