import SwiftUI
import ChitChatCore

struct MicrophoneSetupStepView: View {
    @Environment(AppState.self) private var appState
    @State private var isMonitoring = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Microphone Setup")
                .font(.title)
                .fontWeight(.bold)

            Text("Select your microphone and verify it's working.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                Picker("Input Device", selection: Bindable(appState.settingsManager).settings.selectedMicrophoneId) {
                    Text("System Default").tag(Optional<String>.none)
                    ForEach(appState.availableDevices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio Level")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AudioLevelMeter(level: appState.currentAudioLevel)
                        .frame(height: 12)
                }

                Text("Try speaking to test your microphone.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .task {
            await appState.refreshAudioDevices()
            await appState.startLevelMonitoring()
        }
        .onDisappear {
            Task { await appState.stopLevelMonitoring() }
        }
    }
}
