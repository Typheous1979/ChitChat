import SwiftUI
import ChitChatCore

struct VoiceTrainingView: View {
    @Environment(AppState.self) private var appState
    @State private var trainingManager = VoiceTrainingManager()
    @State private var profiles: [VoiceProfile] = []
    @State private var selectedProfileId: UUID?
    @State private var newProfileName = ""
    @State private var showNewProfileSheet = false
    @State private var currentPrompt: TrainingPrompt?
    @State private var isRecording = false
    @State private var showEnvironmentTest = false

    var body: some View {
        Form {
            profileSection
            trainingSection
            environmentSection
        }
        .formStyle(.grouped)
        .onAppear { refreshProfiles() }
        .sheet(isPresented: $showNewProfileSheet) { newProfileSheet }
        .sheet(isPresented: $showEnvironmentTest) {
            EnvironmentTestView()
                .environment(appState)
                .frame(width: 500, height: 450)
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        Section("Voice Profile") {
            if profiles.isEmpty {
                Text("No voice profiles yet. Create one to improve transcription accuracy.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Active Profile", selection: $selectedProfileId) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(profiles) { profile in
                        HStack {
                            Text(profile.name)
                            if profile.isComplete {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption2)
                            }
                        }
                        .tag(Optional(profile.id))
                    }
                }
                .onChange(of: selectedProfileId) { _, newValue in
                    if let id = newValue {
                        trainingManager.selectProfile(id: id)
                        appState.settingsManager.update { $0.activeVoiceProfileId = id }
                    }
                }
            }

            HStack {
                Button("New Profile") { showNewProfileSheet = true }

                if let id = selectedProfileId {
                    Button("Delete", role: .destructive) {
                        try? trainingManager.deleteProfile(id: id)
                        selectedProfileId = nil
                        refreshProfiles()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Training Section

    private var trainingSection: some View {
        Section("Training") {
            if let profile = trainingManager.currentProfile {
                ProgressView(value: trainingManager.trainingProgress) {
                    HStack {
                        Text("Training Progress")
                        Spacer()
                        Text("\(profile.completedPromptIds.count)/\(TrainingPrompts.all.count) passages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if profile.isComplete {
                    Label("Training complete!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                    LabeledContent("Vocabulary words") {
                        Text("\(profile.customVocabulary.count)")
                    }
                    LabeledContent("Corrections learned") {
                        Text("\(profile.corrections.count)")
                    }
                } else if let prompt = trainingManager.nextTrainingPrompt() {
                    trainingPromptCard(prompt)
                }
            } else {
                Text("Select or create a voice profile to begin training.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func trainingPromptCard(_ prompt: TrainingPrompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(prompt.title, systemImage: "text.quote")
                    .font(.subheadline.bold())
                Spacer()
                Text("~\(Int(prompt.estimatedDuration))s")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(prompt.text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Button {
                    // Recording will use the audio capture service
                    // For now, simulate completion for UI development
                } label: {
                    Label(isRecording ? "Stop Recording" : "Record Passage", systemImage: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(isRecording ? .red : .accentColor)

                if isRecording {
                    LiveWaveformView(audioLevel: appState.currentAudioLevel)
                        .frame(height: 30)
                }
            }
        }
    }

    // MARK: - Environment Section

    private var environmentSection: some View {
        Section("Environment") {
            Button("Test Audio Environment") {
                showEnvironmentTest = true
            }
            Text("Measures background noise and audio quality to optimize transcription.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - New Profile Sheet

    private var newProfileSheet: some View {
        VStack(spacing: 16) {
            Text("New Voice Profile")
                .font(.headline)

            TextField("Profile Name", text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            HStack {
                Button("Cancel") {
                    newProfileName = ""
                    showNewProfileSheet = false
                }
                .buttonStyle(.bordered)

                Button("Create") {
                    if let profile = try? trainingManager.createProfile(name: newProfileName) {
                        selectedProfileId = profile.id
                        refreshProfiles()
                    }
                    newProfileName = ""
                    showNewProfileSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    // MARK: - Helpers

    private func refreshProfiles() {
        profiles = trainingManager.loadProfiles()
        if let activeId = appState.settingsManager.settings.activeVoiceProfileId {
            selectedProfileId = activeId
            trainingManager.selectProfile(id: activeId)
        }
    }
}
