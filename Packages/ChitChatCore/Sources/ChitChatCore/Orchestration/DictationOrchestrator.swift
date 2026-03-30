import Foundation

/// Central pipeline coordinator that wires hotkey -> audio capture -> transcription -> text injection.
///
/// Data flow:
/// 1. Hotkey press triggers `startDictation()`
/// 2. Checks for focused text field (determines injection target)
/// 3. Starts audio capture → AsyncStream<Data>
/// 4. Starts transcription session → AsyncStream<TranscriptionResult>
/// 5. Two concurrent tasks: audio→transcription feed, transcription→text injection
/// 6. Hotkey release triggers `stopDictation()` → final processing → cleanup
@Observable
public final class DictationOrchestrator: @unchecked Sendable {

    public enum State: Sendable, Equatable {
        case idle
        case starting
        case recording
        case processing
        case error(String)
    }

    // Observable state
    public private(set) var state: State = .idle
    public private(set) var currentTranscription: String = ""
    public private(set) var lastFinalText: String = ""
    public private(set) var sessionTranscription: String = ""

    // Services
    private let audioCapture: AudioCaptureService
    private let transcription: any TranscriptionService
    private let textInjection: TextInjectionService
    private let accessibility: AccessibilityService
    private let clipboard: ClipboardService
    private let settingsManager: SettingsManager

    /// Voice training corrections: maps misheard words to correct forms.
    /// Applied as post-processing on transcription results before injection.
    public var corrections: [String: String] = [:]

    /// Filler word filter for idle talk reduction.
    private let fillerWordFilter = FillerWordFilter()

    /// Noise gate filter calibrated from environment test. Nil if not calibrated.
    public var noiseGate: AudioNoiseGate?

    // Internal state
    private let lock = NSLock()
    private var pipelineTask: Task<Void, Never>?
    private var partialCharacterCount: Int = 0
    private var usingClipboardFallback: Bool = false
    private var accumulatedText: String = ""
    private var audioStream: AsyncStream<Data>?
    private var transcriptionStream: AsyncStream<TranscriptionResult>?

    /// Callback for state changes (e.g., to update menu bar icon).
    public var onStateChanged: ((State) -> Void)?

    /// Callback when a transcription is completed (for history).
    public var onTranscriptionCompleted: ((String, Bool) -> Void)?

    public init(
        audioCapture: AudioCaptureService,
        transcription: any TranscriptionService,
        textInjection: TextInjectionService,
        accessibility: AccessibilityService,
        clipboard: ClipboardService,
        settingsManager: SettingsManager
    ) {
        self.audioCapture = audioCapture
        self.transcription = transcription
        self.textInjection = textInjection
        self.accessibility = accessibility
        self.clipboard = clipboard
        self.settingsManager = settingsManager
    }

    // MARK: - Public API

    public var isActive: Bool {
        state == .recording || state == .starting || state == .processing
    }

    /// Start a dictation session. Called when hotkey is pressed.
    public func startDictation() async {
        guard !isActive else { return }

        Log.orchestrator.info("Starting dictation session")
        state = .starting
        onStateChanged?(state)

        // Reset state
        lock.withLock {
            partialCharacterCount = 0
            usingClipboardFallback = false
            accumulatedText = ""
        }
        currentTranscription = ""
        sessionTranscription = ""

        // Determine injection target
        let axGranted = accessibility.isAccessibilityGranted()
        let fieldInfo = axGranted ? await accessibility.focusedTextField() : nil

        if let fieldInfo {
            Log.orchestrator.info("Injecting into \(fieldInfo.applicationName, privacy: .public) (\(fieldInfo.role, privacy: .public))")
        } else {
            // No standard text field detected (or accessibility not granted).
            // Still inject via CGEvent — works for Terminal, non-standard text areas,
            // and any app that accepts keyboard input. CGEvent keystrokes go to
            // whatever app currently has keyboard focus.
            Log.orchestrator.info("No standard text field detected — will inject via CGEvent into active app")
        }

        // Start the pipeline
        pipelineTask = Task { [weak self] in
            await self?.runPipeline()
        }
    }

    /// Stop the dictation session. Called when hotkey is released.
    public func stopDictation() async {
        guard isActive else { return }

        Log.orchestrator.info("Stopping dictation session")
        state = .processing
        onStateChanged?(state)

        // Signal end of audio (blocks until final inference completes)
        await transcription.finishAudio()

        // Stop audio capture
        await audioCapture.stopCapture()

        // Cancel the pipeline task (finishAudio already delivered final results)
        pipelineTask?.cancel()
        pipelineTask = nil

        // Handle clipboard fallback
        let clipboardFallback = lock.withLock { usingClipboardFallback }
        if clipboardFallback && !accumulatedText.isEmpty {
            await clipboard.store(text: accumulatedText, source: "dictation_fallback")
            onTranscriptionCompleted?(accumulatedText, true)
        } else if !sessionTranscription.isEmpty {
            onTranscriptionCompleted?(sessionTranscription, false)
        }

        await transcription.stopSession()

        state = .idle
        onStateChanged?(state)
    }

    /// Toggle dictation on/off. For toggle hotkey mode.
    public func toggleDictation() async {
        if isActive {
            await stopDictation()
        } else {
            await startDictation()
        }
    }

    // MARK: - Pipeline

    private func runPipeline() async {
        do {
            Log.orchestrator.info("Pipeline starting with engine: \(self.transcription.engineName, privacy: .public)")

            // Start audio capture (16kHz, mono)
            let audioStream = try await audioCapture.startCapture(sampleRate: 16000, channels: 1)
            Log.orchestrator.info("Audio capture started")

            // Start transcription session (clean up audio capture on failure)
            let transcriptionStream: AsyncStream<TranscriptionResult>
            do {
                transcriptionStream = try await transcription.startSession(sampleRate: 16000, channels: 1)
            } catch {
                await audioCapture.stopCapture()
                throw error
            }
            Log.orchestrator.info("Transcription session started")

            state = .recording
            onStateChanged?(state)

            // Run two concurrent tasks
            await withTaskGroup(of: Void.self) { group in
                // Task A: Feed audio to transcription
                group.addTask { [weak self] in
                    guard let self else { return }
                    let gate = self.noiseGate
                    let suppressionEnabled = self.settingsManager.settings.noiseSuppression
                    var bufferCount = 0
                    for await buffer in audioStream {
                        guard !Task.isCancelled else { break }
                        let processed = (suppressionEnabled && gate != nil) ? gate!.process(buffer) : buffer
                        await self.transcription.feedAudio(processed)
                        bufferCount += 1
                    }
                    Log.orchestrator.info("Audio feed ended after \(bufferCount) buffers")
                }

                // Task B: Process transcription results
                group.addTask { [weak self] in
                    guard let self else { return }
                    var resultCount = 0
                    for await result in transcriptionStream {
                        guard !Task.isCancelled else { break }
                        resultCount += 1
                        Log.orchestrator.info("Transcription result #\(resultCount): isFinal=\(result.isFinal) text=\"\(result.text, privacy: .public)\"")
                        await self.handleTranscriptionResult(result)
                    }
                    Log.orchestrator.info("Transcription stream ended after \(resultCount) results")
                }
            }
        } catch {
            Log.orchestrator.error("Pipeline error: \(error.localizedDescription, privacy: .public)")
            state = .error(error.localizedDescription)
            onStateChanged?(state)
        }
    }

    // MARK: - Result Handling

    /// Process a transcription result — either partial (interim) or final.
    ///
    /// Incremental injection algorithm:
    /// - Track `partialCharacterCount` (chars of the current partial on screen)
    /// - On partial: delete previous partial chars, type new partial
    /// - On final: delete previous partial chars, type final text, reset counter
    private func handleTranscriptionResult(_ result: TranscriptionResult) async {
        var text = result.text
        let isFinal = result.isFinal

        // Apply voice training corrections (replace misheard words with correct forms)
        if !corrections.isEmpty {
            for (wrong, correct) in corrections {
                text = text.replacingOccurrences(of: wrong, with: correct, options: .caseInsensitive)
            }
        }

        // Apply idle talk reduction (remove filler words)
        if settingsManager.settings.idleTalkReduction {
            text = fillerWordFilter.apply(text)
        }

        // If text is empty after filtering (user only said fillers), clean up
        if text.isEmpty {
            if isFinal {
                let previousPartialCount = lock.withLock { partialCharacterCount }
                if previousPartialCount > 0 {
                    _ = await textInjection.injectIncremental(newText: "", replacingLast: previousPartialCount)
                    lock.withLock { partialCharacterCount = 0 }
                }
            }
            return
        }

        currentTranscription = text

        let clipboardFallback = lock.withLock { usingClipboardFallback }

        if clipboardFallback {
            // Accumulate text for clipboard
            if isFinal {
                lock.withLock {
                    if !accumulatedText.isEmpty && !accumulatedText.hasSuffix(" ") {
                        accumulatedText += " "
                    }
                    accumulatedText += text
                }
                sessionTranscription = lock.withLock { accumulatedText }
            }
            return
        }

        // Inject into focused text field
        let previousPartialCount = lock.withLock { partialCharacterCount }

        if isFinal {
            // Replace partial with final text, optionally add trailing space
            let finalText = settingsManager.settings.addTrailingSpace ? text + " " : text
            _ = await textInjection.injectIncremental(
                newText: finalText,
                replacingLast: previousPartialCount
            )
            lock.withLock { partialCharacterCount = 0 }

            // Append to session transcript
            if !sessionTranscription.isEmpty && !sessionTranscription.hasSuffix(" ") {
                sessionTranscription += " "
            }
            sessionTranscription += text
            lastFinalText = text
        } else {
            // Replace previous partial with updated partial
            _ = await textInjection.injectIncremental(
                newText: text,
                replacingLast: previousPartialCount
            )
            lock.withLock { partialCharacterCount = text.utf16.count }
        }
    }
}

