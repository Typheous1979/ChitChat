import SwiftUI
import ChitChatCore

struct AdvancedFeaturesView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Speech Cleanup") {
                Toggle("Idle Talk Reduction", isOn: Bindable(appState.settingsManager).settings.idleTalkReduction)

                Text("Removes filler words like \"um\", \"uh\", \"you know\", and \"I mean\" from transcription results before they are injected. Uses word-boundary matching to avoid modifying real words.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
