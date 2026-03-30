import AppKit
import SwiftUI
import ChitChatCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    let appState = AppState()
    private var onboardingWindow: NSWindow?
    private var overlayWindow: TranscriptionOverlayWindow?
    private var transcriptionObserver: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusBarController = StatusBarController(appState: appState)
        overlayWindow = TranscriptionOverlayWindow()

        appState.onServicesRebuilt = { [weak self] in
            self?.startTranscriptionObserver()
        }

        if appState.hasCompletedOnboarding {
            Task {
                await appState.bootstrap()
                startTranscriptionObserver()
            }
        } else {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        transcriptionObserver?.cancel()
    }

    // MARK: - Transcription Overlay

    /// Observe the orchestrator's state and current transcription to drive the overlay.
    /// Safe to call multiple times (cancels previous observer).
    func startTranscriptionObserver() {
        transcriptionObserver?.cancel()
        let orchestrator = appState.services.dictationOrchestrator

        // Single unified callback: handles both AppState updates and overlay/icon.
        // Set fresh each time (no chaining) to prevent callback growth on multiple rebuilds.
        orchestrator.onStateChanged = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // AppState updates (recording flag, error display)
                switch state {
                case .recording:
                    self.appState.isRecording = true
                    self.appState.currentTranscription = ""
                case .idle:
                    self.appState.isRecording = false
                    self.appState.currentTranscription = ""
                case .error(let message):
                    self.appState.isRecording = false
                    self.appState.currentError = message
                default:
                    break
                }

                // Overlay and status bar icon
                switch state {
                case .recording:
                    self.statusBarController?.updateIcon(isRecording: true)
                    if self.appState.settingsManager.settings.showTranscriptionOverlay {
                        self.overlayWindow?.showAnimated()
                    }
                case .idle, .error:
                    self.statusBarController?.updateIcon(isRecording: false)
                    self.overlayWindow?.hideAnimated()
                default:
                    break
                }
            }
        }

        // Poll orchestrator's current transcription to update overlay
        transcriptionObserver = Task { [weak self] in
            var lastText = ""
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self else { break }
                let text = orchestrator.currentTranscription
                if text != lastText {
                    lastText = text
                    self.overlayWindow?.updateText(text, isFinal: false)
                    self.appState.currentTranscription = text
                }
            }
        }
    }

    // MARK: - Onboarding

    func showOnboarding() {
        let onboardingView = OnboardingView()
            .environment(appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to ChitChat"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

}
