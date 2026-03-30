import AppKit
import Carbon.HIToolbox
import ChitChatCore

final class MacTextInjectionService: TextInjectionService, @unchecked Sendable {
    private let accessibilityService: AccessibilityService
    private let clipboardService: ClipboardService
    private let eventSource: CGEventSource?
    private let lock = NSLock()

    /// Inter-key delay in microseconds between each CGEvent keystroke.
    /// 500μs is reliable across Terminal, browsers, and native apps.
    /// Lower values (0-100μs) cause garbled output in Chromium browsers and Terminal.
    private let interKeyDelay: UInt32 = 500

    /// Extra pause in microseconds between delete phase and type phase during
    /// incremental injection. Prevents backspaces and new characters from blending.
    private let phaseGapDelay: UInt32 = 2000

    var supportsIncrementalInjection: Bool { true }

    init(accessibilityService: AccessibilityService, clipboardService: ClipboardService) {
        self.accessibilityService = accessibilityService
        self.clipboardService = clipboardService
        self.eventSource = CGEventSource(stateID: .combinedSessionState)
    }

    // MARK: - TextInjectionService

    func injectText(_ text: String) async -> InjectionResult {
        // CGEvent typing works into whatever app has keyboard focus,
        // even without accessibility permission (non-sandboxed app).
        // Only fall back to clipboard if we can confirm no text field is focused
        // AND accessibility is granted (so we trust the detection).
        let axGranted = accessibilityService.isAccessibilityGranted()
        if axGranted {
            let field = await accessibilityService.focusedTextField()
            if field == nil {
                await clipboardService.store(text: text, source: "dictation_fallback")
                return InjectionResult(
                    target: .internalClipboard,
                    injectedText: text,
                    success: true,
                    fallbackReason: "No text field focused"
                )
            }
        }

        typeViaKeyboardEvents(text)
        return InjectionResult(
            target: .focusedTextField,
            injectedText: text,
            success: true
        )
    }

    func injectIncremental(newText: String, replacingLast characterCount: Int) async -> InjectionResult {
        // Delete previous partial characters
        if characterCount > 0 {
            deleteCharacters(count: characterCount)
            // Pause between delete and type phases so the target app
            // finishes processing backspaces before new characters arrive
            usleep(phaseGapDelay)
        }

        // Type the new text via CGEvent (works without AX permission)
        if !newText.isEmpty {
            typeViaKeyboardEvents(newText)
        }

        return InjectionResult(
            target: .focusedTextField,
            injectedText: newText,
            success: true
        )
    }

    func checkPermissions() async -> Bool {
        // CGEvent posting works in non-sandboxed apps even without AX trust,
        // but AX trust is needed for field detection.
        true
    }

    func requestPermissions() async {
        accessibilityService.promptForAccessibility()
    }

    // MARK: - CGEvent Keystroke Simulation

    private func typeViaKeyboardEvents(_ text: String) {
        for char in text {
            typeCharacter(char)
        }
    }

    private func typeCharacter(_ char: Character) {
        let utf16Units = Array(String(char).utf16)

        if let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true) {
            keyDown.keyboardSetUnicodeString(stringLength: utf16Units.count, unicodeString: utf16Units)
            keyDown.post(tap: .cghidEventTap)
        }

        if let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) {
            keyUp.keyboardSetUnicodeString(stringLength: utf16Units.count, unicodeString: utf16Units)
            keyUp.post(tap: .cghidEventTap)
        }

        usleep(interKeyDelay)
    }

    private func deleteCharacters(count: Int) {
        let backspaceKeyCode: CGKeyCode = CGKeyCode(kVK_Delete)

        for _ in 0..<count {
            if let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: backspaceKeyCode, keyDown: true) {
                keyDown.post(tap: .cghidEventTap)
            }
            if let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: backspaceKeyCode, keyDown: false) {
                keyUp.post(tap: .cghidEventTap)
            }
            usleep(interKeyDelay)
        }
    }
}
