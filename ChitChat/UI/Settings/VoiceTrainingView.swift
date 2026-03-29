import SwiftUI
import ChitChatCore

struct VoiceTrainingView: View {
    @Environment(AppState.self) private var appState
    @State private var trainingManager = VoiceTrainingManager()
    @State private var profiles: [VoiceProfile] = []
    @State private var selectedProfileId: UUID?
    @State private var newProfileName = ""
    @State private var showNewProfileSheet = false
    @State private var showEnvironmentTest = false

    // Recording state
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var capturedAudioData = Data()
    @State private var audioAccumulationTask: Task<Void, Never>?
    @State private var lastComparison: TrainingComparison?
    @State private var recordingError: String?

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
                    lastComparison = nil
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

    @ViewBuilder
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

                if profile.completedPromptIds.count > 0 {
                    Button("Reset Training", role: .destructive) {
                        try? trainingManager.resetTraining()
                        lastComparison = nil
                        recordingError = nil
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }

                if profile.isComplete {
                    trainingCompleteView(profile)
                } else if let comparison = lastComparison {
                    comparisonResultView(comparison)
                } else if isTranscribing {
                    transcribingView
                } else if let prompt = trainingManager.nextTrainingPrompt() {
                    trainingPromptCard(prompt)
                }

                if let error = recordingError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                Text("Select or create a voice profile to begin training.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func trainingCompleteView(_ profile: VoiceProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Training complete!", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text("Whisper will use your trained vocabulary to improve accuracy.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("Vocabulary words") {
                Text("\(profile.customVocabulary.count)")
            }
            LabeledContent("Corrections learned") {
                Text("\(profile.corrections.count)")
            }

            if !profile.initialPrompt.isEmpty {
                LabeledContent("Model prompt") {
                    Text(String(profile.initialPrompt.prefix(80)) + (profile.initialPrompt.count > 80 ? "..." : ""))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Button("Retrain from scratch") {
                try? trainingManager.resetTraining()
                lastComparison = nil
            }
            .buttonStyle(.bordered)
            .font(.caption)
        }
    }

    private func comparisonResultView(_ comparison: TrainingComparison) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Result", systemImage: "checkmark.circle")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(Int(comparison.matchRate * 100))% match")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(comparison.matchRate > 0.8 ? .green : .orange)
            }

            Text("What Whisper heard:")
                .font(.caption).foregroundStyle(.tertiary)
            Text(comparison.transcribedText)
                .font(.callout)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))

            if comparison.corrections > 0 {
                Text("\(comparison.corrections) correction\(comparison.corrections == 1 ? "" : "s") learned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Retry Passage") {
                    try? trainingManager.retryLastPrompt()
                    lastComparison = nil
                    recordingError = nil
                }
                .buttonStyle(.bordered)

                Button("Next Passage") {
                    lastComparison = nil
                    recordingError = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var transcribingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Transcribing your recording...")
                .font(.callout)
                .foregroundStyle(.secondary)
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
                if isRecording {
                    Button {
                        stopRecording(prompt: prompt)
                    } label: {
                        Label("Stop Recording", systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    LiveWaveformView(audioLevel: appState.currentAudioLevel)
                        .frame(height: 30)
                } else {
                    Button {
                        startRecording(prompt: prompt)
                    } label: {
                        Label("Record Passage", systemImage: "mic.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appState.isTranscriptionReady)
                }
            }
        }
    }

    // MARK: - Recording Flow

    private func startRecording(prompt: TrainingPrompt) {
        guard !appState.isRecording else {
            recordingError = "Stop dictation before recording a training passage."
            return
        }

        capturedAudioData = Data()
        lastComparison = nil
        recordingError = nil

        Task {
            do {
                // Stop any existing level monitoring to avoid mic contention
                await appState.stopLevelMonitoring()

                let audioStream = try await appState.services.audioCaptureService.startCapture(
                    sampleRate: 16000, channels: 1
                )
                isRecording = true

                audioAccumulationTask = Task {
                    for await buffer in audioStream {
                        guard !Task.isCancelled else { break }
                        capturedAudioData.append(buffer)
                    }
                }
            } catch {
                recordingError = "Failed to start recording: \(error.localizedDescription)"
                isRecording = false
            }
        }
    }

    private func stopRecording(prompt: TrainingPrompt) {
        isRecording = false
        isTranscribing = true

        Task {
            audioAccumulationTask?.cancel()
            audioAccumulationTask = nil
            await appState.services.audioCaptureService.stopCapture()

            guard !capturedAudioData.isEmpty else {
                recordingError = "No audio captured. Try again."
                isTranscribing = false
                return
            }

            do {
                let transcribedText = try await transcribeAudio(capturedAudioData)

                try trainingManager.recordTrainingSample(
                    promptId: prompt.id,
                    expectedText: prompt.text,
                    transcribedText: transcribedText,
                    audioData: capturedAudioData
                )

                let matchRate = calculateMatchRate(expected: prompt.text, transcribed: transcribedText)
                let profile = trainingManager.currentProfile
                let correctionCount = profile?.corrections.count ?? 0

                lastComparison = TrainingComparison(
                    transcribedText: transcribedText,
                    matchRate: matchRate,
                    corrections: correctionCount
                )

                // If training just completed, apply initialPrompt to Whisper
                if let profile, profile.isComplete, !profile.initialPrompt.isEmpty {
                    appState.services.transcriptionCoordinator.setWhisperInitialPrompt(profile.initialPrompt)
                }
            } catch {
                recordingError = "Transcription failed: \(error.localizedDescription)"
            }

            isTranscribing = false
        }
    }

    private func transcribeAudio(_ audioData: Data) async throws -> String {
        guard let service = appState.services.transcriptionCoordinator.resolveService() else {
            throw TranscriptionError.modelNotLoaded
        }

        let resultStream = try await service.startSession(sampleRate: 16000, channels: 1)
        await service.feedAudio(audioData)
        await service.finishAudio()

        var finalText = ""
        for await result in resultStream {
            if result.isFinal {
                finalText = result.text
            }
        }

        await service.stopSession()
        return finalText
    }

    private func calculateMatchRate(expected: String, transcribed: String) -> Double {
        let expectedWords = Set(expected.lowercased().split(separator: " ").map {
            $0.trimmingCharacters(in: .punctuationCharacters)
        })
        let transcribedWords = Set(transcribed.lowercased().split(separator: " ").map {
            $0.trimmingCharacters(in: .punctuationCharacters)
        })
        guard !expectedWords.isEmpty else { return 0 }
        return Double(expectedWords.intersection(transcribedWords).count) / Double(expectedWords.count)
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
                        appState.settingsManager.update { $0.activeVoiceProfileId = profile.id }
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

// MARK: - Models

struct TrainingComparison {
    let transcribedText: String
    let matchRate: Double
    let corrections: Int
}
