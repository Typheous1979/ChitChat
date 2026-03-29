import SwiftUI
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
                Toggle("Show transcription overlay", isOn: Bindable(appState.settingsManager).settings.showTranscriptionOverlay)
                Toggle("Play feedback sounds", isOn: Bindable(appState.settingsManager).settings.playFeedbackSounds)
            }

            Section("Text Injection") {
                Picker("Method", selection: Bindable(appState.settingsManager).settings.injectionMethod) {
                    ForEach(InjectionMethod.allCases, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }

                Toggle("Auto-punctuation", isOn: Bindable(appState.settingsManager).settings.autoPunctuation)
                Toggle("Auto-capitalization", isOn: Bindable(appState.settingsManager).settings.autoCapitalization)
                Toggle("Add trailing space", isOn: Bindable(appState.settingsManager).settings.addTrailingSpace)
            }

            Section("Permissions") {
                HStack {
                    Label("Microphone", systemImage: "mic.fill")
                    Spacer()
                    PermissionStatusBadge(status: PlatformCapabilities.microphoneStatus)
                    if PlatformCapabilities.microphoneStatus != .granted {
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
                    PermissionStatusBadge(status: PlatformCapabilities.accessibilityStatus)
                    if PlatformCapabilities.accessibilityStatus != .granted {
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
