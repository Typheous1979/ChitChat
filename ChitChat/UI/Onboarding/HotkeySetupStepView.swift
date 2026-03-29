import SwiftUI
import ChitChatCore

struct HotkeySetupStepView: View {
    @Environment(AppState.self) private var appState
    @State private var testFeedback: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Hotkey Setup")
                .font(.title)
                .fontWeight(.bold)

            Text("Choose a keyboard shortcut to start and stop dictation.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 20) {
                // Hotkey recorder
                VStack(spacing: 8) {
                    Text("Shortcut")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HotkeyRecorderView(binding: Bindable(appState.settingsManager).settings.hotkeyBinding)
                }

                // Mode picker
                VStack(spacing: 8) {
                    Text("Mode")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: Bindable(appState.settingsManager).settings.hotkeyMode) {
                        ForEach(HotkeyMode.allCases, id: \.self) { mode in
                            VStack(alignment: .leading) {
                                Text(mode.displayName)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)

                    Text(modeDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }

                // Test area
                VStack(spacing: 8) {
                    Text("Try it out:")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text("Press \(appState.settingsManager.settings.hotkeyBinding.displayString) to test")
                        .font(.system(.body, design: .rounded))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                    if let feedback = testFeedback {
                        Label(feedback, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var modeDescription: String {
        switch appState.settingsManager.settings.hotkeyMode {
        case .pushToTalk:
            return "Hold the key to record, release to stop."
        case .toggle:
            return "Press once to start, press again to stop."
        }
    }
}
