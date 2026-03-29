import SwiftUI
import ChitChatCore

struct AudioSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isMonitoring = false

    var body: some View {
        Form {
            Section("Microphone") {
                Picker("Input Device", selection: Bindable(appState.settingsManager).settings.selectedMicrophoneId) {
                    Text("System Default").tag(Optional<String>.none)
                    ForEach(appState.availableDevices) { device in
                        HStack {
                            Text(device.name)
                            if device.isDefault {
                                Text("(Default)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .tag(Optional(device.id))
                    }
                }
                .onChange(of: appState.settingsManager.settings.selectedMicrophoneId) { _, newValue in
                    Task {
                        let device = appState.availableDevices.first { $0.id == newValue }
                        try? await appState.services.audioCaptureService.selectDevice(device)
                    }
                }

                HStack {
                    Text("Level")
                    AudioLevelMeter(level: appState.currentAudioLevel)
                        .frame(height: 8)
                }

                Toggle("Monitor microphone", isOn: $isMonitoring)
                    .onChange(of: isMonitoring) { _, monitoring in
                        Task {
                            if monitoring {
                                await appState.startLevelMonitoring()
                            } else {
                                await appState.stopLevelMonitoring()
                            }
                        }
                    }
            }

            Section("Processing") {
                Toggle("Noise suppression", isOn: Bindable(appState.settingsManager).settings.noiseSuppression)
            }

        }
        .formStyle(.grouped)
        .task {
            await appState.refreshAudioDevices()
        }
        .onDisappear {
            if isMonitoring {
                isMonitoring = false
                Task { await appState.stopLevelMonitoring() }
            }
        }
    }
}
