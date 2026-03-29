import Foundation
@testable import ChitChatCore

// MARK: - Mock Transcription Service

final class MockTranscriptionService: TranscriptionService, @unchecked Sendable {
    var state: TranscriptionState = .idle
    var supportsStreaming: Bool = true
    var engineName: String = "Mock"

    private var continuation: AsyncStream<TranscriptionResult>.Continuation?
    var feedAudioCallCount = 0
    var finishAudioCalled = false
    var stopSessionCalled = false

    func startSession(sampleRate: Int, channels: Int) async throws -> AsyncStream<TranscriptionResult> {
        state = .listening
        return AsyncStream { self.continuation = $0 }
    }

    func feedAudio(_ buffer: Data) async {
        feedAudioCallCount += 1
    }

    func finishAudio() async {
        finishAudioCalled = true
    }

    func stopSession() async {
        stopSessionCalled = true
        continuation?.finish()
        state = .idle
    }

    /// Inject a result from the test side.
    func emitResult(_ result: TranscriptionResult) {
        continuation?.yield(result)
    }
}

// MARK: - Mock Audio Capture Service

final class MockAudioCaptureService: AudioCaptureService, @unchecked Sendable {
    var selectedDevice: AudioDevice? = nil
    var isCapturing: Bool = false
    private var captureContinuation: AsyncStream<Data>.Continuation?

    func availableDevices() async -> [AudioDevice] {
        [AudioDevice(id: "mock-1", name: "Mock Microphone", isDefault: true)]
    }

    func selectDevice(_ device: AudioDevice?) async throws {
        selectedDevice = device
    }

    func startCapture(sampleRate: Int, channels: Int) async throws -> AsyncStream<Data> {
        isCapturing = true
        return AsyncStream { self.captureContinuation = $0 }
    }

    func stopCapture() async {
        isCapturing = false
        captureContinuation?.finish()
    }

    func startLevelMonitoring() async throws -> AsyncStream<AudioLevelInfo> {
        AsyncStream { $0.finish() }
    }

    func stopLevelMonitoring() async {}

    func emitAudioBuffer(_ data: Data) {
        captureContinuation?.yield(data)
    }
}

// MARK: - Mock Text Injection Service

final class MockTextInjectionService: TextInjectionService, @unchecked Sendable {
    var supportsIncrementalInjection: Bool = true
    var injectedTexts: [(text: String, replacedCount: Int)] = []
    var lastInjectionResult: InjectionResult?

    func injectText(_ text: String) async -> InjectionResult {
        let result = InjectionResult(target: .focusedTextField, injectedText: text, success: true)
        lastInjectionResult = result
        return result
    }

    func injectIncremental(newText: String, replacingLast characterCount: Int) async -> InjectionResult {
        injectedTexts.append((text: newText, replacedCount: characterCount))
        let result = InjectionResult(target: .focusedTextField, injectedText: newText, success: true)
        lastInjectionResult = result
        return result
    }

    func checkPermissions() async -> Bool { true }
    func requestPermissions() async {}
}

// MARK: - Mock Accessibility Service

final class MockAccessibilityService: AccessibilityService, @unchecked Sendable {
    var granted = true
    var hasFocusedField = true

    func isAccessibilityGranted() -> Bool { granted }
    func promptForAccessibility() {}

    func focusedTextField() async -> FocusedFieldInfo? {
        guard hasFocusedField else { return nil }
        return FocusedFieldInfo(
            applicationName: "MockApp",
            bundleIdentifier: "com.mock.app",
            role: "AXTextArea",
            supportsValueSetting: true,
            currentValue: ""
        )
    }

    func isTextFieldFocused() async -> Bool { hasFocusedField }
}

// MARK: - Mock Clipboard Service

final class MockClipboardService: ClipboardService, @unchecked Sendable {
    var storedEntries: [ClipboardEntry] = []

    func store(text: String, source: String) async {
        storedEntries.append(ClipboardEntry(text: text, source: source))
    }

    func recentEntries(limit: Int) async -> [ClipboardEntry] {
        Array(storedEntries.prefix(limit))
    }

    func copyToSystemClipboard(entry: ClipboardEntry) async {}
    func clearAll() async { storedEntries.removeAll() }
}

// MARK: - Mock Hotkey Service

final class MockHotkeyService: HotkeyService, @unchecked Sendable {
    var currentBinding: HotkeyBinding?
    var isRegistered = false
    private var continuation: AsyncStream<HotkeyEvent>.Continuation?

    func register(binding: HotkeyBinding) async throws -> AsyncStream<HotkeyEvent> {
        currentBinding = binding
        isRegistered = true
        return AsyncStream { self.continuation = $0 }
    }

    func unregister() async {
        isRegistered = false
        currentBinding = nil
        continuation?.finish()
        continuation = nil
    }

    func checkPermissions() async -> Bool { true }

    /// Emit a hotkey event from the test side.
    func emitEvent(_ event: HotkeyEvent) {
        continuation?.yield(event)
    }
}

// MARK: - Mock Voice Profile Service

final class MockVoiceProfileService: VoiceProfileService, @unchecked Sendable {
    var profiles: [VoiceProfile] = []
    var activeProfileId: UUID?

    func listProfiles() async -> [VoiceProfile] { profiles }

    func activeProfile() async -> VoiceProfile? {
        profiles.first(where: { $0.id == activeProfileId })
    }

    func createProfile(name: String) async throws -> VoiceProfile {
        let profile = VoiceProfile(name: name)
        profiles.append(profile)
        return profile
    }

    func deleteProfile(id: UUID) async throws {
        profiles.removeAll(where: { $0.id == id })
        if activeProfileId == id { activeProfileId = nil }
    }

    func setActiveProfile(id: UUID) async throws {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileId = id
    }
}
