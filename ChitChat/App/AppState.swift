import AVFoundation
import Foundation
import SwiftUI
import ChitChatCore

@Observable
@MainActor
final class AppState {
    // Recording
    var isRecording = false
    var currentTranscription = ""
    var recordingDuration: TimeInterval = 0

    // Audio
    var currentAudioLevel: Float = 0
    var availableDevices: [AudioDevice] = []

    // Permissions
    var isMicrophoneGranted = false
    var isAccessibilityGranted = false

    // Onboarding
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    // Settings
    let settingsManager = SettingsManager()

    // Services (not tracked by Observable)
    @ObservationIgnored
    private(set) lazy var services = ServiceContainer(settingsManager: settingsManager)

    // Whisper model manager (observable for download progress UI)
    let whisperModelManager = WhisperModelManager()

    // Recent transcriptions (persisted to UserDefaults)
    var recentTranscriptions: [RecentTranscription] = [] {
        didSet { persistRecentTranscriptions() }
    }

    // Error display
    var currentError: String? {
        didSet {
            if currentError != nil {
                // Auto-dismiss after 8 seconds
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(8))
                    if self.currentError == oldValue {
                        self.currentError = nil
                    }
                }
            }
        }
    }

    // Connection test state
    var connectionTestResult: ConnectionTestResult?

    // Hotkey
    @ObservationIgnored
    private var hotkeyTask: Task<Void, Never>?
    @ObservationIgnored
    private var permissionPollTask: Task<Void, Never>?

    var allPermissionsGranted: Bool {
        isMicrophoneGranted && isAccessibilityGranted
    }

    /// Whether the current transcription engine is ready to use.
    /// Reads observable properties so SwiftUI views reactively update.
    var isTranscriptionReady: Bool {
        let engine = settingsManager.settings.transcriptionEngine
        if engine == .whisperCpp {
            // Read modelChangeCount to track download/delete changes
            let _ = whisperModelManager.modelChangeCount
            return whisperModelManager.isModelDownloaded(settingsManager.settings.whisperModel)
        }
        return true // Deepgram readiness checked at connection time
    }

    // MARK: - Initialization

    func bootstrap() async {
        // Load persisted data
        loadRecentTranscriptions()

        // Check permissions
        isMicrophoneGranted = await checkMicrophonePermission()
        refreshAccessibilityStatus()

        // If accessibility is not granted, clear any stale TCC entry (from a
        // previous build with a different code signature) and re-prompt so the
        // system creates a fresh entry for the current binary.
        if !isAccessibilityGranted {
            resetAccessibilityPermission()
            services.accessibilityService.promptForAccessibility()
        }

        // Start polling accessibility status (it can change at any time via System Settings)
        startPermissionPolling()

        // Register hotkey
        await registerHotkey()

        // Set up orchestrator callbacks
        setupOrchestratorCallbacks()
    }

    /// Refresh accessibility status from the system.
    func refreshAccessibilityStatus() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }

    /// Clear stale accessibility TCC entry left by a previous build.
    /// After a rebuild the code signature changes, making the old entry invalid.
    /// Resetting lets `promptForAccessibility()` create a fresh entry.
    private func resetAccessibilityPermission() {
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", "com.justinkalicharan.chitchat"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    /// Poll accessibility permission every second so we detect changes
    /// made in System Settings without requiring an app restart.
    private func startPermissionPolling() {
        permissionPollTask?.cancel()
        permissionPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { break }
                let granted = AXIsProcessTrusted()
                if self.isAccessibilityGranted != granted {
                    self.isAccessibilityGranted = granted
                }
            }
        }
    }

    // MARK: - Hotkey Management

    func registerHotkey() async {
        hotkeyTask?.cancel()

        let binding = settingsManager.settings.hotkeyBinding
        do {
            let eventStream = try await services.hotkeyService.register(binding: binding)

            hotkeyTask = Task { [weak self] in
                for await event in eventStream {
                    guard let self else { break }
                    let mode = self.settingsManager.settings.hotkeyMode
                    await self.handleHotkeyEvent(event, mode: mode)
                }
            }
        } catch {
            currentError = "Failed to register hotkey: \(error.localizedDescription)"
        }
    }

    private func handleHotkeyEvent(_ event: HotkeyEvent, mode: HotkeyMode) async {
        // Block recording if Whisper is selected but no model is downloaded
        if !isTranscriptionReady {
            if event == .pressed {
                currentError = "No Whisper model downloaded for \(settingsManager.settings.whisperModel.displayName). Open Settings > Transcription to download or select a downloaded model."
            }
            return
        }

        switch mode {
        case .pushToTalk:
            switch event {
            case .pressed:
                await services.dictationOrchestrator.startDictation()
            case .released:
                await services.dictationOrchestrator.stopDictation()
            }
        case .toggle:
            if event == .pressed {
                await services.dictationOrchestrator.toggleDictation()
            }
        }
    }

    // MARK: - Orchestrator Callbacks

    private func setupOrchestratorCallbacks() {
        services.dictationOrchestrator.onStateChanged = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .recording:
                    self.isRecording = true
                    self.currentTranscription = ""
                case .idle:
                    self.isRecording = false
                    self.currentTranscription = ""
                case .error(let message):
                    self.isRecording = false
                    self.currentError = message
                default:
                    break
                }
            }
        }

        services.dictationOrchestrator.onTranscriptionCompleted = { [weak self] text, wasClipboardFallback in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let entry = RecentTranscription(
                    text: text,
                    timestamp: Date(),
                    target: wasClipboardFallback ? "Clipboard" : "Text Field"
                )
                self.recentTranscriptions.insert(entry, at: 0)
                if self.recentTranscriptions.count > 20 {
                    self.recentTranscriptions.removeLast()
                }
            }
        }
    }

    // MARK: - Transcription Rebuild

    /// Call after saving a Deepgram API key or switching engines.
    /// Rebuilds the transcription coordinator and orchestrator with the new configuration.
    /// Called after services are rebuilt — allows AppDelegate to rewire overlay/icon observers.
    var onServicesRebuilt: (() -> Void)?

    func rebuildTranscription() {
        services.rebuildTranscription()
        setupOrchestratorCallbacks()
        onServicesRebuilt?()
    }

    // MARK: - Audio Device Management

    func refreshAudioDevices() async {
        availableDevices = await services.audioCaptureService.availableDevices()
    }

    func startLevelMonitoring() async {
        do {
            let stream = try await services.audioCaptureService.startLevelMonitoring()
            for await level in stream {
                self.currentAudioLevel = level.rmsLevel
            }
        } catch {
            // Level monitoring is non-critical
        }
    }

    func stopLevelMonitoring() async {
        await services.audioCaptureService.stopLevelMonitoring()
        currentAudioLevel = 0
    }

    // MARK: - Transcription Test

    func testDeepgramConnection() async {
        connectionTestResult = .testing
        let result = await services.transcriptionCoordinator.testDeepgramConnection()
        switch result {
        case .success(let message):
            connectionTestResult = .success(message)
        case .failure(let error):
            connectionTestResult = .failure(error.localizedDescription)
        }
        // Auto-clear after 5 seconds
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            connectionTestResult = nil
        }
    }

    // MARK: - Recent Transcriptions Persistence

    private static let recentTranscriptionsKey = "com.chitchat.recentTranscriptions"

    func loadRecentTranscriptions() {
        guard let data = UserDefaults.standard.data(forKey: Self.recentTranscriptionsKey),
              let decoded = try? JSONDecoder().decode([RecentTranscription].self, from: data) else { return }
        recentTranscriptions = decoded
    }

    private func persistRecentTranscriptions() {
        let trimmed = Array(recentTranscriptions.prefix(20))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: Self.recentTranscriptionsKey)
        }
    }

    // MARK: - Permissions

    private func checkMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }
}

struct RecentTranscription: Identifiable, Codable {
    let id: UUID
    let text: String
    let timestamp: Date
    let target: String

    init(text: String, timestamp: Date, target: String) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
        self.target = target
    }
}

enum ConnectionTestResult {
    case testing
    case success(String)
    case failure(String)
}
