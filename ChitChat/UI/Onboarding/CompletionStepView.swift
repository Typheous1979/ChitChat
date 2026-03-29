import SwiftUI
import ChitChatCore

struct CompletionStepView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)

            Text("ChitChat is ready to use.\nPress \(appState.settingsManager.settings.hotkeyBinding.displayString) anywhere to start dictating.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 12) {
                summaryRow(icon: "mic.fill", label: "Microphone", value: appState.availableDevices.first(where: { $0.id == appState.settingsManager.settings.selectedMicrophoneId })?.name ?? "System Default")
                summaryRow(icon: "text.bubble.fill", label: "Engine", value: appState.settingsManager.settings.transcriptionEngine.displayName)
                summaryRow(icon: "keyboard", label: "Hotkey", value: appState.settingsManager.settings.hotkeyBinding.displayString)
                summaryRow(icon: "hand.tap.fill", label: "Mode", value: appState.settingsManager.settings.hotkeyMode.displayName)
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 60)

            Spacer()
        }
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}
