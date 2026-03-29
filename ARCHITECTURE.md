# Architecture

This document describes ChitChat's system design, module boundaries, data flows, and key implementation decisions.

## Design Goals

1. **Cross-platform readiness** — All business logic lives in `ChitChatCore`, a pure Swift package with no Apple UI framework imports. macOS-specific code (AppKit, CoreAudio, CGEvent) is isolated in the app target. This enables a future Windows port by replacing only the platform layer.
2. **Protocol-driven services** — Every system capability is defined as a protocol in ChitChatCore and implemented per-platform in the app target. Services are injected via `ServiceContainer`.
3. **Async-first** — All data flows use `AsyncStream` and Swift concurrency. No callback-based APIs leak into business logic.
4. **Non-sandboxed** — Required for CGEvent posting, AXUIElement queries, and global hotkeys. Distributed via Developer ID signing, not the Mac App Store.

## Module Structure

```
┌─────────────────────────────────────────────────────┐
│                    ChitChat (App)                    │
│                                                     │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────┐  │
│  │  SwiftUI │  │  AppKit  │  │ Platform Services │  │
│  │  Views   │  │  Hybrid  │  │  (Mac*)           │  │
│  └────┬─────┘  └────┬─────┘  └────────┬──────────┘  │
│       │              │                 │             │
│       └──────┬───────┘                 │             │
│              │                         │             │
│     ┌────────▼──────────┐    ┌─────────▼──────────┐  │
│     │     AppState      │    │  ServiceContainer  │  │
│     │   (@MainActor)    │◄───│   (DI wiring)      │  │
│     └───────────────────┘    └────────────────────┘  │
│                                        │             │
├────────────────────────────────────────┼─────────────┤
│              ChitChatCore (SPM)        │             │
│                                        │             │
│     ┌──────────────────────┐   ┌───────▼──────────┐  │
│     │    Protocols/        │   │ DictationOrch-   │  │
│     │  (service contracts) │◄──│  estrator        │  │
│     └──────────────────────┘   └──────────────────┘  │
│                                                     │
│     ┌──────────────┐  ┌────────────┐  ┌──────────┐  │
│     │ Transcription│  │   Audio    │  │  Models  │  │
│     │  Engines     │  │  Analysis  │  │  Enums   │  │
│     └──────────────┘  └────────────┘  └──────────┘  │
└─────────────────────────────────────────────────────┘
```

## Service Protocols

Seven protocols define the platform abstraction layer. Each is in `ChitChatCore/Protocols/`:

| Protocol | Responsibility | macOS Implementation | Underlying API |
|----------|---------------|---------------------|----------------|
| `TranscriptionService` | Speech-to-text engine | `DeepgramStreamingService` / `WhisperCppService` | WebSocket / SwiftWhisper |
| `AudioCaptureService` | Microphone input | `MacAudioCaptureService` | AVAudioEngine + CoreAudio |
| `TextInjectionService` | Type text into apps | `MacTextInjectionService` | CGEvent Unicode keystrokes |
| `HotkeyService` | Global keyboard shortcuts | `MacHotkeyService` | Carbon RegisterEventHotKey |
| `AccessibilityService` | Detect focused text fields | `MacAccessibilityService` | AXUIElement |
| `ClipboardService` | Clipboard storage | `MacClipboardService` | NSPasteboard |
| `VoiceProfileService` | User voice profiles | `VoiceProfileStore` | File-based JSON |

## Dependency Injection

`ServiceContainer` (in `ChitChat/Platform/`) constructs all services in dependency order:

```
ServiceContainer
├── SettingsManager (loads AppSettings from disk)
├── KeychainHelper (Deepgram API key storage)
├── MacAudioCaptureService
├── MacAccessibilityService
├── MacClipboardService
├── MacTextInjectionService (depends on: accessibility, clipboard)
├── MacHotkeyService
├── TranscriptionCoordinator (depends on: settings, API key, model path)
│   ├── DeepgramStreamingService (if API key present)
│   └── WhisperCppService (if model downloaded)
└── DictationOrchestrator (depends on: all services above)
```

Call `rebuildTranscription()` when the API key changes or the transcription engine is switched.

## Core Data Flow

### Dictation Pipeline

```
1. Hotkey Press
   └─► MacHotkeyService (Carbon callback → AsyncStream<HotkeyEvent>)
       └─► AppState.handleHotkeyEvent()
           ├─► Checks isTranscriptionReady (blocks if Whisper model missing)
           └─► DictationOrchestrator.startDictation()

2. Start Dictation
   ├─► AccessibilityService.focusedTextField() — informational only, does NOT gate injection
   └─► runPipeline() launches withTaskGroup:

       Task A: Audio Feed
       AudioCaptureService.startCapture(16kHz, mono)
         → AsyncStream<Data> (Float32 PCM)
         → transcription.feedAudio(buffer) for each chunk

       Task B: Result Processing
       TranscriptionService.startSession()
         → AsyncStream<TranscriptionResult>
         → Noise token filtering (strips [MUSIC], [BLANK_AUDIO], etc.)
         → handleTranscriptionResult() for each result
         → TextInjectionService.injectIncremental() via CGEvent

3. Hotkey Release
   └─► DictationOrchestrator.stopDictation()
       ├─► transcription.finishAudio() (triggers final inference, 10s timeout)
       ├─► audioCapture.stopCapture()
       ├─► 300ms grace period for final results
       ├─► Cancel pipeline task
       └─► transcription.stopSession()
```

### Incremental Text Injection

The orchestrator maintains a `partialCharacterCount` to enable smooth in-place text replacement:

```
Partial result "Hello"       → type "Hello"                    (count: 5)
Partial result "Hello wor"   → delete 5, type "Hello wor"      (count: 9)
Partial result "Hello world" → delete 9, type "Hello world"     (count: 11)
Final result   "Hello world" → delete 11, type "Hello world "   (count: 0, +space if addTrailingSpace enabled)
```

Deletion uses CGEvent backspace keystrokes. Typing uses CGEvent Unicode keystrokes via `keyboardSetUnicodeString()`. The trailing space on final results is controlled by the `addTrailingSpace` setting (read from `SettingsManager`).

### Text Injection in Terminal and Non-Standard Apps

CGEvent keystroke injection works universally — including Terminal.app, iTerm2, and other apps whose AX roles don't match standard text field roles. The orchestrator always injects via CGEvent regardless of `focusedTextField()` result. No automatic clipboard fallback occurs.

### Clipboard Fallback (Manual Only)

Clipboard fallback is NOT triggered automatically. Transcription results are always available in "Recent" in the menu bar popover for manual copy. Automatic clipboard fallback was removed because it silently intercepted text meant for Terminal and other non-standard apps.

Previously when accessibility detected no focused text field:
1. `usingClipboardFallback` flag was set
2. Final results are accumulated (not injected)
3. On session end, accumulated text is stored via `ClipboardService`
4. User can paste manually

## Transcription Engines

### Deepgram (Streaming)

- Connects via WebSocket to Deepgram's Nova-3 API
- Sends Int16 linear PCM audio (converted from Float32 via `AudioFormatConverter`)
- Receives partial and final results in real-time
- Requires internet and API key (stored in Keychain)

### Whisper (Offline)

- Uses [SwiftWhisper](https://github.com/exPHAT/SwiftWhisper), a Swift wrapper around whisper.cpp
- Loads GGML model files downloaded by `WhisperModelManager` from Hugging Face
- Models stored at `~/Library/Application Support/ChitChat/Models/`
- Available sizes: Tiny (75MB), Base (142MB), Small (466MB), Medium (1.5GB), Large-v3 (3GB)
- **Model caching**: `cachedWhisper` persists across recording sessions — first hotkey press loads model, subsequent presses are instant
- Audio buffered during `feedAudio()`, inference runs:
  - Periodically (~3s, min 1s new audio) for partial results during recording
  - Once on `finishAudio()` for the final result (10s timeout)
- Inference serialized via `isInferring` flag (whisper model is not thread-safe)
- **Noise token filtering**: Regex strips all `[BRACKETED]` and `(parenthesized)` whisper.cpp annotations (music, birds, blank audio, laughter, etc.) before emitting results
- **Model readiness guard**: `AppState.isTranscriptionReady` blocks recording if selected model not downloaded, shows error directing user to Settings
- **Must build Release** — Debug builds lack compiler optimization, making inference extremely slow. Tiny model recommended for best performance.

### Engine Selection

`TranscriptionCoordinator` resolves the active engine based on user preference with automatic fallback:

```
User preference: Whisper → Check model downloaded → Use Whisper
                                                  → Fallback to Deepgram (if API key)
User preference: Deepgram → Check API key exists  → Use Deepgram
                                                  → Fallback to Whisper (if model)
Neither available → PlaceholderTranscriptionService (error on start)
```

## Audio Pipeline

```
Microphone → AVAudioEngine (device sample rate)
  → AVAudioConverter → Float32 PCM, 16kHz, mono
  → AsyncStream<Data> (1024-frame buffers)
  ├─► TranscriptionService.feedAudio()
  │   ├─► Whisper: consumed directly as [Float]
  │   └─► Deepgram: converted to Int16 via AudioFormatConverter
  └─► AudioLevelAnalyzer (optional, for UI meters)
```

## State Management

Four `@Observable` classes drive SwiftUI reactivity:

| Class | Actor | Role |
|-------|-------|------|
| `AppState` | `@MainActor` | Top-level UI state, bridges orchestrator → UI |
| `SettingsManager` | None (NSLock) | Persistent settings, read/write AppSettings |
| `DictationOrchestrator` | None (NSLock) | Pipeline state, transcription text |
| `TranscriptionCoordinator` | None (NSLock) | Engine selection, service availability |

All use `@unchecked Sendable` with `NSLock` for manual thread safety.

## UI Architecture

### Menu Bar (NSStatusItem)

- `StatusBarController` manages the status item and its popover
- Icon changes between idle (outline) and recording (filled red)
- Popover uses `MenuBarView` (SwiftUI) for status, controls, and navigation

### Transcription Overlay (NSWindow)

- `TranscriptionOverlayWindow` — borderless, floating, transparent, `ignoresMouseEvents = true`
- Positions near cursor when recording starts
- Shows live transcription text via `OverlayState` (@Observable)
- Does NOT steal focus from the target application
- Configurable: can be disabled in Settings (`showTranscriptionOverlay`)

### Settings (SwiftUI)

- Tab-based settings view: General, Audio, Transcription, Voice Training, About
- Opened via `@Environment(\.openSettings)` with `NSApp.activate()`
- Permission status badges with real-time polling

### Onboarding

- 6-step first-run wizard: Welcome → Permissions → Microphone → Engine → Hotkey → Complete
- Tracks completion via `hasCompletedOnboarding` in settings

## Concurrency Patterns

- **AsyncStream** for all data flow: audio buffers, transcription results, hotkey events, audio levels, noise warnings
- **withTaskGroup** in `DictationOrchestrator.runPipeline()` for concurrent audio feed + result processing
- **NSLock** for protecting shared mutable state in `@Observable` classes
- **Continuation safety**: Always extract continuation from lock before calling `finish()` to prevent deadlock (onTermination handler may re-enter the lock)
- **Task cancellation**: Checked via `Task.isCancelled` in all async loops

## Audio Processing Pipeline

### Environment-Calibrated Noise Gate

`AudioNoiseGate` (`ChitChatCore/Audio/AudioNoiseGate.swift`) filters background noise during dictation:

1. **Calibration**: Environment test (Settings > Voice Training) runs two 5-second phases:
   - Phase 1: Silence — measures noise floor (dB)
   - Phase 2: Speech — measures voice level (dB), calculates SNR
2. **Gate threshold**: `noiseFloor + adaptiveOffset` where offset scales with SNR:
   - SNR < 10 dB (noisy): 8 dB offset (aggressive gating)
   - SNR 10-20 dB (moderate): 5 dB offset
   - SNR >= 20 dB (quiet): 3 dB offset
3. **Per-buffer filtering**: In `DictationOrchestrator.runPipeline()`, each audio buffer's RMS is compared to threshold. Below = zeroed (silence). Above = passed through unchanged.
4. **Persistence**: Calibration stored in `AppSettings` (`calibratedNoiseFloorDb`, `calibratedSpeechLevelDb`, `calibratedSNR`). Loaded by `ServiceContainer.applyNoiseGate()` on startup.
5. **Toggle**: Controlled by `noiseSuppression` setting in Audio preferences.

### Mic Contention

`MacAudioCaptureService` uses separate `AVAudioEngine` instances for level monitoring and capture. Both open the same mic input and compete. Always call `stopLevelMonitoring()` before `startCapture()`.

## Voice Training

### Training Flow

1. User creates a voice profile and records 10 passages from `TrainingPrompts.all`
2. Each recording is transcribed by the active engine, compared word-by-word to expected text
3. `VoiceTrainingManager.recordTrainingSample()` builds:
   - **Corrections dictionary**: `[misheardWord: correctWord]` — applied as post-processing
   - **Custom vocabulary**: correctly transcribed words (>3 chars)
   - **Initial prompt**: actual passage texts with corrections applied (whisper.cpp's `initial_prompt` needs example sentences, not vocabulary lists)
4. On completion, `ServiceContainer` loads the profile and applies both prompt and corrections

### How Training Improves Transcription

Two mechanisms:
- **Whisper initial_prompt biasing**: `WhisperCppService.setInitialPrompt()` sets `whisper_full_params.initial_prompt` with example sentences, conditioning the model toward the user's vocabulary and speaking patterns
- **Corrections post-processing**: `DictationOrchestrator.handleTranscriptionResult()` replaces known misheard words before text injection

### Data Persistence

- Profiles: `~/Library/Application Support/ChitChat/VoiceProfiles/{UUID}.json`
- Recordings: `~/Library/Application Support/ChitChat/VoiceProfiles/{UUID}/recordings/`
- Active profile ID: `AppSettings.activeVoiceProfileId`
- Deleting a profile removes all data; corrections and prompt are cleared on next restart

## Permissions

| Permission | Why Needed | How Checked |
|------------|-----------|-------------|
| Microphone | Audio capture | `AVCaptureDevice.requestAccess(for: .audio)` |
| Accessibility | Text injection + focused field detection | `AXIsProcessTrusted()`, polled every 1s |

Both are required for full functionality. Without accessibility, CGEvent posting to other apps silently fails.
