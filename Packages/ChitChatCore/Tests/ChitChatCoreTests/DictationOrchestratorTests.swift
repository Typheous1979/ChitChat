import Foundation
import Testing
@testable import ChitChatCore

@Suite("DictationOrchestrator Tests")
struct DictationOrchestratorTests {

    private func makeSUT() -> (
        orchestrator: DictationOrchestrator,
        transcription: MockTranscriptionService,
        audio: MockAudioCaptureService,
        injection: MockTextInjectionService,
        accessibility: MockAccessibilityService,
        clipboard: MockClipboardService
    ) {
        let transcription = MockTranscriptionService()
        let audio = MockAudioCaptureService()
        let injection = MockTextInjectionService()
        let accessibility = MockAccessibilityService()
        let clipboard = MockClipboardService()

        let orchestrator = DictationOrchestrator(
            audioCapture: audio,
            transcription: transcription,
            textInjection: injection,
            accessibility: accessibility,
            clipboard: clipboard
        )

        return (orchestrator, transcription, audio, injection, accessibility, clipboard)
    }

    @Test("Starts and stops dictation correctly")
    func startStop() async {
        let (orchestrator, transcription, audio, _, _, _) = makeSUT()

        #expect(orchestrator.state == .idle)
        #expect(!orchestrator.isActive)

        await orchestrator.startDictation()

        // Give pipeline time to start
        try? await Task.sleep(for: .milliseconds(50))

        #expect(orchestrator.isActive)
        #expect(audio.isCapturing)

        await orchestrator.stopDictation()

        #expect(orchestrator.state == .idle)
        #expect(transcription.finishAudioCalled)
        #expect(transcription.stopSessionCalled)
    }

    @Test("Incremental injection: partial results replace previous partial")
    func incrementalInjection() async {
        let (orchestrator, transcription, _, injection, _, _) = makeSUT()

        await orchestrator.startDictation()
        try? await Task.sleep(for: .milliseconds(50))

        // Simulate partial results
        transcription.emitResult(TranscriptionResult(text: "Hello", isFinal: false))
        try? await Task.sleep(for: .milliseconds(50))

        transcription.emitResult(TranscriptionResult(text: "Hello world", isFinal: false))
        try? await Task.sleep(for: .milliseconds(50))

        // Check: first partial replaced 0 chars, second replaced 5 ("Hello")
        #expect(injection.injectedTexts.count >= 2)
        if injection.injectedTexts.count >= 2 {
            #expect(injection.injectedTexts[0].text == "Hello")
            #expect(injection.injectedTexts[0].replacedCount == 0)
            #expect(injection.injectedTexts[1].text == "Hello world")
            #expect(injection.injectedTexts[1].replacedCount == 5)
        }

        await orchestrator.stopDictation()
    }

    @Test("Final result resets partial counter")
    func finalResultResetsPartial() async {
        let (orchestrator, transcription, _, injection, _, _) = makeSUT()

        await orchestrator.startDictation()
        try? await Task.sleep(for: .milliseconds(50))

        // Partial then final
        transcription.emitResult(TranscriptionResult(text: "Hi", isFinal: false))
        try? await Task.sleep(for: .milliseconds(50))

        transcription.emitResult(TranscriptionResult(text: "Hi there", isFinal: true))
        try? await Task.sleep(for: .milliseconds(50))

        // Next partial should replace 0 (counter was reset by final)
        transcription.emitResult(TranscriptionResult(text: "How", isFinal: false))
        try? await Task.sleep(for: .milliseconds(50))

        #expect(injection.injectedTexts.count >= 3)
        if injection.injectedTexts.count >= 3 {
            // "How" should replace 0 chars (partial counter reset)
            #expect(injection.injectedTexts[2].replacedCount == 0)
        }

        await orchestrator.stopDictation()
    }

    @Test("Clipboard fallback when no text field focused")
    func clipboardFallback() async {
        let (orchestrator, transcription, _, _, accessibility, clipboard) = makeSUT()

        // No text field focused
        accessibility.hasFocusedField = false

        await orchestrator.startDictation()
        try? await Task.sleep(for: .milliseconds(50))

        transcription.emitResult(TranscriptionResult(text: "Hello world", isFinal: true))
        try? await Task.sleep(for: .milliseconds(50))

        await orchestrator.stopDictation()

        // Text should have been stored in clipboard
        #expect(clipboard.storedEntries.count == 1)
        #expect(clipboard.storedEntries.first?.text == "Hello world")
    }
}
