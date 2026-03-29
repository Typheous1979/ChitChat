import Foundation

public struct FocusedFieldInfo: Sendable {
    public let applicationName: String
    public let bundleIdentifier: String?
    public let role: String
    public let supportsValueSetting: Bool
    public let currentValue: String?

    public init(applicationName: String, bundleIdentifier: String?, role: String, supportsValueSetting: Bool, currentValue: String?) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.role = role
        self.supportsValueSetting = supportsValueSetting
        self.currentValue = currentValue
    }
}

/// Protocol for querying system accessibility state.
public protocol AccessibilityService: AnyObject, Sendable {
    /// Check if accessibility permissions are granted.
    func isAccessibilityGranted() -> Bool

    /// Prompt user to grant accessibility access.
    func promptForAccessibility()

    /// Get info about the currently focused text input field.
    func focusedTextField() async -> FocusedFieldInfo?

    /// Whether any text input field is currently focused.
    func isTextFieldFocused() async -> Bool
}
