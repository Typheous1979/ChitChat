import SwiftUI
import ChitChatCore

struct EngineSetupStepView: View {
    @Environment(AppState.self) private var appState
    @State private var apiKeyInput = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Transcription Engine")
                .font(.title)
                .fontWeight(.bold)

            Text("Choose how ChitChat converts your speech to text.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                engineCard(
                    engine: .deepgram,
                    icon: "cloud.fill",
                    title: "Deepgram",
                    subtitle: "Best accuracy, requires internet",
                    features: ["Sub-300ms latency", "Nova-3 model", "Smart punctuation"]
                )

                engineCard(
                    engine: .whisperCpp,
                    icon: "desktopcomputer",
                    title: "Whisper (Offline)",
                    subtitle: "Private, no internet needed",
                    features: ["Runs locally", "Multiple model sizes", "Apple Silicon optimized"]
                )
            }
            .padding(.horizontal, 40)

            if appState.settingsManager.settings.transcriptionEngine == .deepgram {
                VStack(spacing: 6) {
                    SecureField("Deepgram API Key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveApiKey() }

                    if isApiKeySaved {
                        Label("API key saved", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 40)
            }

            Spacer()
        }
        .onAppear { loadApiKey() }
        .onDisappear { saveApiKey() }
    }

    @State private var isApiKeySaved = false

    private func saveApiKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        appState.services.keychain.set(trimmed, forKey: "deepgram_api_key")
        appState.rebuildTranscription()
        isApiKeySaved = true
    }

    private func loadApiKey() {
        if let existing = appState.services.keychain.get("deepgram_api_key") {
            apiKeyInput = existing
            isApiKeySaved = true
        }
    }

    private func engineCard(engine: TranscriptionEngine, icon: String, title: String, subtitle: String, features: [String]) -> some View {
        let isSelected = appState.settingsManager.settings.transcriptionEngine == engine

        return Button {
            appState.settingsManager.update { $0.transcriptionEngine = engine }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(features, id: \.self) { feature in
                            Text(feature)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(12)
            .background(
                isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : .secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
