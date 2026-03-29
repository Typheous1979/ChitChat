import AppKit
import ApplicationServices
import ChitChatCore

final class MacAccessibilityService: AccessibilityService, @unchecked Sendable {

    // MARK: - Permission Checks

    func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Focused Field Detection

    func focusedTextField() async -> FocusedFieldInfo? {
        let systemWide = AXUIElementCreateSystemWide()

        // Get the focused application
        var focusedApp: AnyObject?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )
        guard appResult == .success else { return nil }

        // Get the focused UI element from the focused app
        var focusedElement: AnyObject?
        let elemResult = AXUIElementCopyAttributeValue(
            focusedApp as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard elemResult == .success else { return nil }

        let element = focusedElement as! AXUIElement

        // Get the role
        guard let role = getStringAttribute(element, kAXRoleAttribute) else { return nil }

        // Check if this is a text-input role
        let textRoles: Set<String> = [
            kAXTextFieldRole,
            kAXTextAreaRole,
            kAXComboBoxRole,
            "AXSearchField",
            "AXWebArea",
        ]
        guard textRoles.contains(role) else { return nil }

        // Check if the value attribute is settable
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)

        // Get current value
        let currentValue = getStringAttribute(element, kAXValueAttribute)

        // Get app info
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let app = NSRunningApplication(processIdentifier: pid)

        return FocusedFieldInfo(
            applicationName: app?.localizedName ?? "Unknown",
            bundleIdentifier: app?.bundleIdentifier,
            role: role,
            supportsValueSetting: settable.boolValue,
            currentValue: currentValue
        )
    }

    func isTextFieldFocused() async -> Bool {
        await focusedTextField() != nil
    }

    // MARK: - AX Helpers

    private func getStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }
}
