import Foundation

/// Manages voice training sessions: recording passages, analyzing transcription accuracy,
/// and building voice profiles with custom vocabulary and correction maps.
@Observable
public final class VoiceTrainingManager: @unchecked Sendable {
    public private(set) var currentProfile: VoiceProfile?
    public private(set) var trainingProgress: Float = 0.0
    public private(set) var isRecordingPassage = false

    private let profileStore: VoiceProfileStore
    private let lock = NSLock()

    public init(profileStore: VoiceProfileStore = VoiceProfileStore()) {
        self.profileStore = profileStore
    }

    // MARK: - Profile Management

    public func loadProfiles() -> [VoiceProfile] {
        (try? profileStore.listProfiles()) ?? []
    }

    public func createProfile(name: String) throws -> VoiceProfile {
        let profile = VoiceProfile(name: name)
        try profileStore.saveProfile(profile)
        currentProfile = profile
        trainingProgress = 0
        return profile
    }

    public func selectProfile(id: UUID) {
        currentProfile = try? profileStore.loadProfile(id: id)
        updateProgress()
    }

    public func deleteProfile(id: UUID) throws {
        try profileStore.deleteProfile(id: id)
        if currentProfile?.id == id {
            currentProfile = nil
            trainingProgress = 0
        }
    }

    // MARK: - Training Flow

    /// Get the next training prompt that hasn't been recorded yet.
    public func nextTrainingPrompt() -> TrainingPrompt? {
        guard let profile = currentProfile else { return nil }
        let recordedIds = Set(profile.completedPromptIds)
        return TrainingPrompts.all.first { !recordedIds.contains($0.id) }
    }

    /// Record a training sample: save audio, transcribe, compare, and update profile.
    public func recordTrainingSample(
        promptId: String,
        expectedText: String,
        transcribedText: String,
        audioData: Data
    ) throws {
        guard var profile = currentProfile else { return }

        // Save the recording
        _ = try profileStore.saveRecording(
            profileId: profile.id,
            promptId: promptId,
            audioData: audioData
        )

        // Analyze differences between expected and transcribed
        let corrections = findCorrections(expected: expectedText, transcribed: transcribedText)
        for (wrong, correct) in corrections {
            profile.corrections[wrong] = correct
        }

        // Extract words that were correctly transcribed for vocabulary boosting
        let correctWords = extractMatchingWords(expected: expectedText, transcribed: transcribedText)
        let uniqueNew = correctWords.filter { !profile.customVocabulary.contains($0) }
        profile.customVocabulary.append(contentsOf: uniqueNew)

        // Mark this prompt as completed
        profile.completedPromptIds.append(promptId)

        // Check if training is complete
        if profile.completedPromptIds.count >= TrainingPrompts.all.count {
            profile.isComplete = true
            profile.initialPrompt = buildInitialPrompt(from: profile)
        }

        try profileStore.saveProfile(profile)
        currentProfile = profile
        updateProgress()
    }

    /// Remove the last completed prompt so it can be re-recorded.
    public func retryLastPrompt() throws {
        guard var profile = currentProfile, !profile.completedPromptIds.isEmpty else { return }
        profile.completedPromptIds.removeLast()
        profile.isComplete = false
        profile.initialPrompt = ""
        try profileStore.saveProfile(profile)
        currentProfile = profile
        updateProgress()
    }

    /// Reset all training progress for the current profile.
    public func resetTraining() throws {
        guard var profile = currentProfile else { return }
        profile.completedPromptIds.removeAll()
        profile.corrections.removeAll()
        profile.customVocabulary.removeAll()
        profile.isComplete = false
        profile.initialPrompt = ""
        try profileStore.saveProfile(profile)
        currentProfile = profile
        updateProgress()
    }

    /// Remove a single correction from the active profile.
    public func deleteCorrection(key: String) throws {
        guard var profile = currentProfile else { return }
        profile.corrections.removeValue(forKey: key)
        try profileStore.saveProfile(profile)
        currentProfile = profile
    }

    // MARK: - Analysis

    /// Find words that were mistranscribed.
    /// Only creates corrections when the misheard word is similar to the expected word
    /// (edit distance ≤ 2), preventing wild misalignments like "about" → "appointment".
    private func findCorrections(expected: String, transcribed: String) -> [(String, String)] {
        let expectedWords = expected.lowercased().split(separator: " ").map(String.init)
        let transcribedWords = transcribed.lowercased().split(separator: " ").map(String.init)

        var corrections: [(String, String)] = []

        let minCount = min(expectedWords.count, transcribedWords.count)
        for i in 0..<minCount {
            let exp = expectedWords[i].trimmingCharacters(in: .punctuationCharacters)
            let got = transcribedWords[i].trimmingCharacters(in: .punctuationCharacters)

            // Skip single-char words and identical words
            guard exp != got, exp.count >= 2, got.count >= 2 else { continue }

            // Only correct similar words (edit distance ≤ 2)
            // This prevents positional misalignment from creating nonsense corrections
            if Self.editDistance(got, exp) <= 2 {
                corrections.append((got, exp))
            }
        }

        return corrections
    }

    /// Levenshtein edit distance between two strings.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = curr
        }
        return prev[n]
    }

    /// Extract words that were correctly transcribed (for vocabulary boosting).
    private func extractMatchingWords(expected: String, transcribed: String) -> [String] {
        let expectedSet = Set(expected.lowercased().split(separator: " ").map {
            $0.trimmingCharacters(in: .punctuationCharacters)
        })
        let transcribedSet = Set(transcribed.lowercased().split(separator: " ").map {
            $0.trimmingCharacters(in: .punctuationCharacters)
        })
        return Array(expectedSet.intersection(transcribedSet)).filter { $0.count > 3 }
    }

    /// Build an initial prompt for Whisper from the completed training passages.
    /// whisper.cpp's initial_prompt conditions the model on example transcription text —
    /// feeding it real sentences the user spoke is far more effective than a vocabulary list.
    private func buildInitialPrompt(from profile: VoiceProfile) -> String {
        // Use the actual training passage texts as example transcriptions.
        // Apply learned corrections so Whisper sees the correct word forms.
        let completedTexts = TrainingPrompts.all
            .filter { profile.completedPromptIds.contains($0.id) }
            .map { prompt in
                var text = prompt.text
                // Apply corrections so the prompt contains correct forms
                for (wrong, correct) in profile.corrections {
                    text = text.replacingOccurrences(
                        of: wrong, with: correct,
                        options: .caseInsensitive
                    )
                }
                return text
            }

        // whisper.cpp truncates initial_prompt to ~224 tokens, so keep it concise.
        // Join passages and truncate to ~500 chars.
        let joined = completedTexts.joined(separator: " ")
        if joined.count > 500 {
            return String(joined.prefix(500))
        }
        return joined
    }

    private func updateProgress() {
        guard let profile = currentProfile else {
            trainingProgress = 0
            return
        }
        let total = Float(TrainingPrompts.all.count)
        trainingProgress = Float(profile.completedPromptIds.count) / total
    }
}
