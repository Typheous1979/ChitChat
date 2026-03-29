import SwiftUI
import ChitChatCore

struct TranscriptionSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var apiKeyInput = ""
    @State private var isApiKeyVisible = false
    @State private var isApiKeySaved = false

    var body: some View {
        Form {
            Section("Engine") {
                Picker("Transcription Engine", selection: Bindable(appState.settingsManager).settings.transcriptionEngine) {
                    ForEach(TranscriptionEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appState.settingsManager.settings.transcriptionEngine) { _, _ in
                    appState.rebuildTranscription()
                }

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(engineDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if appState.settingsManager.settings.transcriptionEngine == .deepgram {
                deepgramSettings
            } else {
                whisperSettings
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadApiKey()
        }
    }

    private var engineDescription: String {
        switch appState.settingsManager.settings.transcriptionEngine {
        case .deepgram:
            return "Cloud-based transcription with sub-300ms latency. Requires internet and a Deepgram API key."
        case .whisperCpp:
            return "On-device transcription for privacy. No internet required. Download a model to get started."
        }
    }

    // MARK: - Deepgram Settings

    private var deepgramSettings: some View {
        Section("Deepgram") {
            HStack {
                if isApiKeyVisible {
                    TextField("API Key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } else {
                    SecureField("API Key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                }
                Button(isApiKeyVisible ? "Hide" : "Show") {
                    isApiKeyVisible.toggle()
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Button("Save API Key") {
                    appState.services.keychain.set(apiKeyInput, forKey: "deepgram_api_key")
                    isApiKeySaved = true
                    appState.rebuildTranscription()
                }
                .disabled(apiKeyInput.isEmpty)

                if isApiKeySaved {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Saved to Keychain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Model") {
                Text("Nova-3")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Language") {
                Text(appState.settingsManager.settings.deepgramLanguage.uppercased())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Test Connection") {
                    // Save the key first if it's been entered
                    if !apiKeyInput.isEmpty {
                        appState.services.keychain.set(apiKeyInput, forKey: "deepgram_api_key")
                    }
                    Task { await appState.testDeepgramConnection() }
                }

                connectionStatus
            }
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        switch appState.connectionTestResult {
        case .testing:
            ProgressView()
                .scaleEffect(0.6)
            Text("Testing...")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .success(let message):
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let error):
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        case .none:
            EmptyView()
        }
    }

    // MARK: - Whisper Settings

    @ViewBuilder
    private var whisperSettings: some View {
        Section("Whisper (Offline)") {
            Picker("Model Size", selection: Bindable(appState.settingsManager).settings.whisperModel) {
                ForEach(WhisperModelSize.allCases, id: \.self) { size in
                    HStack {
                        Text(size.displayName)
                        if appState.whisperModelManager.isModelDownloaded(size) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption2)
                        }
                    }
                    .tag(size)
                }
            }
            .onChange(of: appState.settingsManager.settings.whisperModel) { _, _ in
                appState.rebuildTranscription()
            }

            LabeledContent("Language") {
                Text(appState.settingsManager.settings.whisperLanguage.uppercased())
                    .foregroundStyle(.secondary)
            }
        }

        Section("Model Management") {
            let selected = appState.settingsManager.settings.whisperModel
            let isDownloaded = appState.whisperModelManager.isModelDownloaded(selected)
            let manager = appState.whisperModelManager

            if manager.isDownloading {
                // Download in progress
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Downloading \(manager.currentDownloadModel?.rawValue ?? selected.rawValue)...")
                            .font(.callout)
                        Spacer()
                        Text("\(Int(manager.downloadProgress * 100))%")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: manager.downloadProgress)

                    Button("Cancel Download", role: .destructive) {
                        manager.cancelDownload()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            } else if isDownloaded {
                // Model exists
                HStack {
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    if let bytes = manager.downloadedModelSize(selected) {
                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Delete Model", role: .destructive) {
                    try? manager.deleteModel(selected)
                    appState.rebuildTranscription()
                }
                .buttonStyle(.borderless)
            } else {
                // Not downloaded
                Label("Not Downloaded", systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)

                Button("Download \(selected.displayName)") {
                    Task {
                        do {
                            try await manager.downloadModel(selected)
                            appState.rebuildTranscription()
                        } catch {
                            // Error is stored in manager.downloadError
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            if let error = manager.downloadError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Show all downloaded models
            let downloaded = manager.downloadedModels()
            if downloaded.count > 1 || (downloaded.count == 1 && downloaded.first != selected) {
                Divider()
                Text("Downloaded Models")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                ForEach(downloaded, id: \.self) { model in
                    HStack {
                        Text(model.displayName)
                            .font(.callout)
                        if model == selected {
                            Text("Active")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.15), in: Capsule())
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        if let bytes = manager.downloadedModelSize(model) {
                            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        if model != selected {
                            Button("Use") {
                                appState.settingsManager.update { $0.whisperModel = model }
                                appState.rebuildTranscription()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)

                            Button("Delete") {
                                try? manager.deleteModel(model)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func loadApiKey() {
        if let savedKey = appState.services.keychain.get("deepgram_api_key") {
            apiKeyInput = savedKey
            isApiKeySaved = true
        }
    }
}
