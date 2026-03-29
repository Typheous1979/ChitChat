import AppKit
import Carbon.HIToolbox
import ChitChatCore

/// Global hotkey registration using Carbon's RegisterEventHotKey API.
/// Works even when the app is not in focus.
final class MacHotkeyService: HotkeyService, @unchecked Sendable {
    private let lock = NSLock()
    private var _currentBinding: HotkeyBinding?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var continuation: AsyncStream<HotkeyEvent>.Continuation?

    /// Shared instance needed for the C callback to route events.
    fileprivate static var shared: MacHotkeyService?

    var currentBinding: HotkeyBinding? {
        lock.withLock { _currentBinding }
    }

    func register(binding: HotkeyBinding) async throws -> AsyncStream<HotkeyEvent> {
        // Unregister any existing hotkey
        await unregister()

        lock.withLock {
            _currentBinding = binding
            MacHotkeyService.shared = self
        }

        // Install the Carbon event handler (once)
        installCarbonHandler()

        // Register the hotkey
        let hotKeyID = EventHotKeyID(signature: fourCharCode("CHIT"), id: 1)
        let carbonModifiers = carbonModifierFlags(from: binding.modifiers)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr else {
            throw HotkeyError.registrationFailed
        }

        lock.withLock { self.hotKeyRef = ref }

        return AsyncStream { continuation in
            self.lock.withLock { self.continuation = continuation }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.unregister() }
            }
        }
    }

    func unregister() async {
        lock.withLock {
            if let ref = hotKeyRef {
                UnregisterEventHotKey(ref)
                hotKeyRef = nil
            }
            if let handler = eventHandlerRef {
                RemoveEventHandler(handler)
                eventHandlerRef = nil
            }
            continuation?.finish()
            continuation = nil
            _currentBinding = nil
        }
    }

    func checkPermissions() async -> Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Carbon Event Handler

    private func installCarbonHandler() {
        guard lock.withLock({ eventHandlerRef }) == nil else { return }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        var handlerRef: EventHandlerRef?
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyCallback,
            eventTypes.count,
            &eventTypes,
            nil,
            &handlerRef
        )

        lock.withLock { self.eventHandlerRef = handlerRef }
    }

    /// Called from the C callback when our hotkey fires.
    fileprivate func handleHotkeyEvent(_ event: HotkeyEvent) {
        lock.withLock { continuation }?.yield(event)
    }

    // MARK: - Helpers

    private func carbonModifierFlags(from cgFlags: UInt32) -> UInt32 {
        var carbon: UInt32 = 0
        if cgFlags & UInt32(NX_DEVICELCMDKEYMASK) != 0 || cgFlags & UInt32(NX_COMMANDMASK) != 0 {
            carbon |= UInt32(cmdKey)
        }
        if cgFlags & UInt32(NX_DEVICELALTKEYMASK) != 0 || cgFlags & UInt32(NX_ALTERNATEMASK) != 0 {
            carbon |= UInt32(optionKey)
        }
        if cgFlags & UInt32(NX_DEVICELCTLKEYMASK) != 0 || cgFlags & UInt32(NX_CONTROLMASK) != 0 {
            carbon |= UInt32(controlKey)
        }
        if cgFlags & UInt32(NX_DEVICELSHIFTKEYMASK) != 0 || cgFlags & UInt32(NX_SHIFTMASK) != 0 {
            carbon |= UInt32(shiftKey)
        }
        return carbon
    }

    private func fourCharCode(_ string: String) -> OSType {
        let chars = Array(string.utf8)
        guard chars.count == 4 else { return 0 }
        return OSType(chars[0]) << 24 | OSType(chars[1]) << 16 | OSType(chars[2]) << 8 | OSType(chars[3])
    }
}

// MARK: - Carbon Callback (C-compatible)

private func carbonHotkeyCallback(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    let eventKind = GetEventKind(event)
    let hotkeyEvent: HotkeyEvent

    switch Int(eventKind) {
    case kEventHotKeyPressed:
        hotkeyEvent = .pressed
    case kEventHotKeyReleased:
        hotkeyEvent = .released
    default:
        return OSStatus(eventNotHandledErr)
    }

    MacHotkeyService.shared?.handleHotkeyEvent(hotkeyEvent)
    return noErr
}

// MARK: - Errors

enum HotkeyError: Error, LocalizedError {
    case registrationFailed

    var errorDescription: String? {
        switch self {
        case .registrationFailed:
            return "Failed to register global hotkey. The key combination may be in use by another application."
        }
    }
}
