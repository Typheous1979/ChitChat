# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Generate Xcode project (required after adding/removing files)
/tmp/xcodegen/xcodegen/bin/xcodegen generate

# Build the app (Debug)
xcodebuild -project ChitChat.xcodeproj -scheme ChitChat -configuration Debug build

# Build the app (Release — required for Whisper performance)
xcodebuild -project ChitChat.xcodeproj -scheme ChitChat -configuration Release build

# Build ChitChatCore package only
cd Packages/ChitChatCore && swift build

# Run all ChitChatCore tests (62 tests, 10 suites)
cd Packages/ChitChatCore && swift test

# Run a single test suite
cd Packages/ChitChatCore && swift test --filter DictationOrchestratorTests

# Run a single test
cd Packages/ChitChatCore && swift test --filter "Starts and stops dictation"
```

Tests use **Swift Testing** (not XCTest). Use `@Test`, `#expect`, `@Suite`.

## Architecture

**Two-module structure** designed for future Windows port:

- **`ChitChatCore`** (local SPM package at `Packages/ChitChatCore/`) — All platform-agnostic logic: protocols, models, transcription engines, audio analysis, voice training, orchestration. No AppKit/SwiftUI imports. Depends on SwiftWhisper.
- **`ChitChat`** (Xcode app target) — macOS-specific UI (SwiftUI + AppKit hybrid) and platform service implementations (CGEvent, AXUIElement, AVAudioEngine, Carbon hotkeys).

### Protocol-Driven Services

Seven service protocols defined in `ChitChatCore/Protocols/` with macOS implementations in `ChitChat/Services/`:

| Protocol | macOS Implementation | Underlying API |
|----------|---------------------|----------------|
| `TranscriptionService` | `DeepgramStreamingService` / `WhisperCppService` | WebSocket / SwiftWhisper (whisper.cpp) |
| `AudioCaptureService` | `MacAudioCaptureService` | AVAudioEngine + CoreAudio |
| `TextInjectionService` | `MacTextInjectionService` | CGEvent Unicode keystrokes |
| `HotkeyService` | `MacHotkeyService` | Carbon RegisterEventHotKey |
| `AccessibilityService` | `MacAccessibilityService` | AXUIElement |
| `ClipboardService` | `MacClipboardService` | NSPasteboard |
| `VoiceProfileService` | `VoiceProfileStore` | File-based JSON |

### Dependency Injection

`ServiceContainer` (`ChitChat/Platform/ServiceContainer.swift`) constructs all services in dependency order and wires them into `DictationOrchestrator`. Created lazily by `AppState`. Call `rebuildTranscription()` when transcription engine or API key changes. Guarded against rebuild during active dictation.

### Core Data Flow

```
Hotkey Press → AppState.handleHotkeyEvent()
  → Checks isTranscriptionReady (blocks if Whisper model missing)
  → DictationOrchestrator.startDictation()
    → AccessibilityService.focusedTextField() — informational only
    → Always injects via CGEvent (works in Terminal, browsers, all apps)
    → Two concurrent tasks in withTaskGroup:
        Task A: AudioCaptureService.startCapture() → noise gate filter → feedAudio() to transcription
        Task B: TranscriptionService results → noise filtering → corrections post-processing → TextInjectionService.injectIncremental()
  → Hotkey Release → stopDictation() → finishAudio() → cleanup
```

### Text Injection

CGEvent Unicode keystrokes are always used for text injection — no automatic clipboard fallback. This works in Terminal.app, iTerm2, browsers, editors, and any app that accepts keyboard input. The `AccessibilityService.focusedTextField()` check is informational (for logging), not a gate.

### Incremental Injection Algorithm

`DictationOrchestrator` tracks `partialCharacterCount`. On each partial result: delete N previous characters via backspace CGEvents, type new text. On final result: delete partial, type final + optional trailing space (controlled by `addTrailingSpace` setting), reset counter to 0.

### State Management

`@Observable` classes (`AppState`, `SettingsManager`, `DictationOrchestrator`, `TranscriptionCoordinator`) drive SwiftUI reactivity. `AppState` is `@MainActor` and bridges orchestrator callbacks to UI state. `AppState.isTranscriptionReady` is a reactive computed property that checks if the current engine has a model available.

## Key Conventions

- **Non-sandboxed app** — Required for CGEvent posting, AXUIElement queries, and global hotkeys. Distributed via Developer ID, not Mac App Store.
- **API keys in Keychain** — Never UserDefaults. Access via `KeychainHelper` with key `"deepgram_api_key"`.
- **`@unchecked Sendable`** — Used on `@Observable` classes that manage their own thread safety via `NSLock`.
- **AsyncStream everywhere** — Audio capture, transcription results, hotkey events, level monitoring, and noise warnings all flow through `AsyncStream`.
- **OSLog logging** — Use `Log.orchestrator`, `Log.transcription`, `Log.audio`, etc. from `ChitChatCore/Utilities/Logger.swift`.
- **NSLock deadlock risk** — Never call `continuation.finish()` inside a lock if `onTermination` also acquires the same lock. Extract the continuation first, then finish outside the lock.
- **Audio format** — AVAudioEngine captures Float32 PCM at 16kHz mono. `AudioFormatConverter.float32ToInt16()` converts for Deepgram's `linear16` encoding. WhisperCppService consumes Float32 directly as `[Float]`.
- **SwiftWhisper dependency** — `WhisperCppService` uses [SwiftWhisper](https://github.com/exPHAT/SwiftWhisper) (SPM, branch: master) for offline inference. Loads GGML models downloaded by `WhisperModelManager`. Model is cached across sessions (`cachedWhisper`). Emits periodic partial results (~3s intervals) and a final result on `finishAudio()` with 10s timeout.
- **Noise token filtering** — `WhisperCppService.stripNoiseTokens()` uses regex `\[.*?\]|\(.*?\)` to remove all whisper.cpp annotations like `[BLANK_AUDIO]`, `[MUSIC PLAYING IN THE BACKGROUND]`, `[BIRDS CHIRPING]`, `(laughing)`, etc. If only noise tokens remain, no result is emitted.
- **Noise gate filter** — `AudioNoiseGate` (ChitChatCore/Audio/) applies per-buffer gating calibrated from environment test. Mutes buffers below threshold (noise floor + adaptive offset based on SNR). Global setting stored in `AppSettings.calibratedNoiseFloorDb/calibratedSpeechLevelDb/calibratedSNR`. Controlled by `noiseSuppression` toggle. Applied in DictationOrchestrator's audio feed loop. Loaded by `ServiceContainer.applyNoiseGate()` on startup and rebuild.
- **Voice training** — 10-passage training via `VoiceTrainingManager`. Builds `initialPrompt` from actual passage texts (not vocabulary list — whisper.cpp needs example sentences). Corrections dictionary applied as post-processing in `DictationOrchestrator.handleTranscriptionResult()` using word-boundary regex (not substring replacement). Corrections require edit distance ≤ 2 to prevent misalignment noise. Users can review and delete individual corrections in the Training UI. Profile data persisted in `~/Library/Application Support/ChitChat/VoiceProfiles/`. Loaded by `ServiceContainer.applyVoiceProfilePrompt()`.
- **C string lifetime for initial_prompt** — `strdup()` before `whisper.transcribe()`, free AFTER it returns. Do NOT use `defer` — transcribe dispatches to background queue, defer would free the pointer before inference runs.
- **Mic contention** — `MacAudioCaptureService` uses separate `AVAudioEngine` instances for level monitoring and capture. Always call `stopLevelMonitoring()` before `startCapture()` to avoid contention. Affects EnvironmentTestView and VoiceTrainingView.
- **Whisper performance** — Always build **Release** when testing Whisper. Debug builds compile whisper.cpp without `-O3` optimization. Tiny model (75MB) recommended for best speed. Model cached after first load.
- **Menu bar app** — `LSUIElement=true` in Info.plist. `NSApp.setActivationPolicy(.accessory)`. No dock icon.
- **Permission auto-reset** — On startup, if microphone or accessibility is denied, the app runs `tccutil reset {service} com.justinkalicharan.chitchat` to clear stale TCC entries from previous builds, then re-prompts. Both permissions polled every 1 second for real-time UI updates.
- **Model readiness guard** — `AppState.isTranscriptionReady` blocks recording if Whisper is selected but no model is downloaded. Shows error message directing user to Settings.
- **Reactive model status** — `WhisperModelManager.modelChangeCount` is an `@Observable` property incremented on download/delete. Views read it to trigger re-renders for filesystem-dependent state like `isModelDownloaded()`.
- **Launch at login** — Uses `SMAppService.mainApp.register()/unregister()` via onChange handler. Takes effect immediately when toggled.
- **CGEvent inter-key delay** — `MacTextInjectionService.interKeyDelay` is 500μs. Lower values (0-100μs) cause garbled output in browsers and Terminal because `virtualKey: 0` needs time for the Unicode override to apply. A 2ms `phaseGapDelay` separates the delete and type phases during incremental injection.
- **Unimplemented settings** — `playFeedbackSounds`, `autoPunctuation`, `autoCapitalization`, `injectionMethod` are hidden from the UI (not disabled with "Coming soon" — removed entirely). `addTrailingSpace` IS wired and functional.
- **Removed dead settings** — `showMenuBarIcon` and `enableLogging` were removed (never used). Old serialized settings with these keys are safely ignored by `JSONDecoder`.
- **xcodegen** — Run `xcodegen generate` after adding/removing source files to regenerate the `.xcodeproj` from `project.yml`.
- **gh CLI** — Installed at `~/bin/gh` (not in system PATH). Use full path for GitHub operations.

## Test Mocks

All service mocks are in `Tests/ChitChatCoreTests/Mocks/MockServices.swift`:
- `MockTranscriptionService` — `emitResult()` injects transcription results into pipeline
- `MockAudioCaptureService` — `emitAudioBuffer()` feeds audio data
- `MockTextInjectionService` — Records `injectedTexts` array for verification
- `MockAccessibilityService` — `hasFocusedField` controls text field detection
- `MockClipboardService` — Records `storedEntries`
- `MockHotkeyService` — `emitEvent()` simulates hotkey press/release
- `MockVoiceProfileService` — In-memory profile CRUD
