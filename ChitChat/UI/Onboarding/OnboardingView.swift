import SwiftUI
import ChitChatCore

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var currentStep = 0

    private let totalSteps = 6

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)

            // Step content
            Group {
                switch currentStep {
                case 0: WelcomeStepView()
                case 1: PermissionsStepView()
                case 2: MicrophoneSetupStepView()
                case 3: EngineSetupStepView()
                case 4: HotkeySetupStepView()
                case 5: CompletionStepView()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if currentStep < totalSteps - 1 {
                    Button("Continue") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canContinue)
                } else {
                    Button("Get Started") {
                        appState.hasCompletedOnboarding = true
                        Task { await appState.bootstrap() }
                        NSApp.keyWindow?.close()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
    }

    /// Gate: require permissions (step 1) and engine config (step 3) before advancing.
    private var canContinue: Bool {
        switch currentStep {
        case 1:
            // Permissions step — require at least microphone
            return appState.isMicrophoneGranted
        case 3:
            // Engine setup — require API key or downloaded model
            let engine = appState.settingsManager.settings.transcriptionEngine
            if engine == .deepgram {
                let key = appState.services.keychain.get("deepgram_api_key") ?? ""
                return !key.isEmpty
            } else {
                return appState.whisperModelManager.isModelDownloaded(appState.settingsManager.settings.whisperModel)
            }
        default:
            return true
        }
    }
}
