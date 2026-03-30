import SwiftUI
import ServiceManagement
import ChitChatCore

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Hotkey") {
                LabeledContent("Shortcut") {
                    HotkeyRecorderView(binding: Bindable(appState.settingsManager).settings.hotkeyBinding)
                }
                .onChange(of: appState.settingsManager.settings.hotkeyBinding) { _, _ in
                    Task { await appState.registerHotkey() }
                }

                Picker("Mode", selection: Bindable(appState.settingsManager).settings.hotkeyMode) {
                    ForEach(HotkeyMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Text(hotkeyModeDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Behavior") {
                Toggle("Launch at login", isOn: Bindable(appState.settingsManager).settings.launchAtLogin)
                    .onChange(of: appState.settingsManager.settings.launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            Log.general.error("Launch at login failed: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                Toggle("Show transcription overlay", isOn: Bindable(appState.settingsManager).settings.showTranscriptionOverlay)
            }

            Section("Text Injection") {
                Toggle("Add trailing space", isOn: Bindable(appState.settingsManager).settings.addTrailingSpace)
            }

            Section("History") {
                Picker("Max recent transcriptions", selection: Bindable(appState.settingsManager).settings.maxRecentTranscriptions) {
                    ForEach([10, 20, 30, 40, 50], id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
            }

            Section("Speech Cleanup") {
                Toggle("Idle Talk Reduction", isOn: Bindable(appState.settingsManager).settings.idleTalkReduction)
                Text("Removes filler words like \"um\", \"uh\", and \"you know\" from transcription results.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack {
                    Label("Microphone", systemImage: "mic.fill")
                    Spacer()
                    PermissionStatusBadge(status: appState.isMicrophoneGranted ? .granted : .denied)
                    if !appState.isMicrophoneGranted {
                        Button("Open Settings") {
                            PlatformCapabilities.openMicrophoneSettings()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }

                HStack {
                    Label("Accessibility", systemImage: "lock.shield")
                    Spacer()
                    PermissionStatusBadge(status: appState.isAccessibilityGranted ? .granted : .denied)
                    if !appState.isAccessibilityGranted {
                        Button("Open Settings") {
                            PlatformCapabilities.openAccessibilitySettings()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var hotkeyModeDescription: String {
        switch appState.settingsManager.settings.hotkeyMode {
        case .pushToTalk:
            return "Hold the hotkey to record. Release to stop and inject text."
        case .toggle:
            return "Press the hotkey once to start recording, press again to stop."
        }
    }
}
