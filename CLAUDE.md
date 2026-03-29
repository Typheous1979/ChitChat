# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Generate Xcode project (required after adding/removing files)
/tmp/xcodegen/xcodegen/bin/xcodegen generate

# Build the app
xcodebuild -project ChitChat.xcodeproj -scheme ChitChat -configuration Debug build

# Build ChitChatCore package only
cd Packages/ChitChatCore && swift build

# Run all ChitChatCore tests (27 tests, 8 suites)
cd Packages/ChitChatCore && swift test

# Run a single test suite
cd Packages/ChitChatCore && swift test --filter DictationOrchestratorTests

# Run a single test
cd Packages/ChitChatCore && swift test --filter "Starts and stops dictation"
```

Tests use **Swift Testing** (not XCTest). Use `@Test`, `#expect`, `@Suite`.

## Architecture

**Two-module structure** designed for future Windows port:

- **`ChitChatCore`** (local SPM package at `Packages/ChitChatCore/`) — All platform-agnostic logic: protocols, models, transcription engines, audio analysis, voice training, orchestration. No AppKit/SwiftUI imports.
- **`ChitChat`** (Xcode app target) — macOS-specific UI (SwiftUI + AppKit hybrid) and platform service implementations (CGEvent, AXUIElement, AVAudioEngine, Carbon hotkeys).

### Protocol-Driven Services

Seven service protocols defined in `ChitChatCore/Protocols/` with macOS implementations in `ChitChat/Services/`:

| Protocol | macOS Implementation | Underlying API |
|----------|---------------------|----------------|
| `TranscriptionService` | `DeepgramStreamingService` / `WhisperCppService` | WebSocket / whisper.cpp |
| `AudioCaptureService` | `MacAudioCaptureService` | AVAudioEngine + CoreAudio |
| `TextInjectionService` | `MacTextInjectionService` | CGEvent Unicode keystrokes |
| `HotkeyService` | `MacHotkeyService` | Carbon RegisterEventHotKey |
| `AccessibilityService` | `MacAccessibilityService` | AXUIElement |
| `ClipboardService` | `MacClipboardService` | NSPasteboard |
| `VoiceProfileService` | `VoiceProfileStore` | File-based JSON |

### Dependency Injection

`ServiceContainer` (`ChitChat/Platform/ServiceContainer.swift`) constructs all services in dependency order and wires them into `DictationOrchestrator`. Created lazily by `AppState`. Call `rebuildOrchestrator()` when transcription engine or API key changes.

### Core Data Flow

```
Hotkey Press → MacHotkeyService (Carbon callback → AsyncStream<HotkeyEvent>)
  → AppState.handleHotkeyEvent()
  → DictationOrchestrator.startDictation()
    → AccessibilityService.focusedTextField() — determines injection target
    → Two concurrent tasks in withTaskGroup:
        Task A: AudioCaptureService.startCapture() → feedAudio() to transcription
        Task B: TranscriptionService results → TextInjectionService.injectIncremental()
  → Hotkey Release → stopDictation() → finishAudio() → cleanup
```

### Incremental Injection Algorithm

`DictationOrchestrator` tracks `partialCharacterCount`. On each partial result: delete N previous characters via backspace CGEvents, type new text. On final result: delete partial, type final + trailing space, reset counter to 0. If no text field focused, accumulates text for clipboard fallback.

### State Management

`@Observable` classes (`AppState`, `SettingsManager`, `DictationOrchestrator`, `TranscriptionCoordinator`) drive SwiftUI reactivity. `AppState` is `@MainActor` and bridges orchestrator callbacks to UI state.

## Key Conventions

- **Non-sandboxed app** — Required for CGEvent posting, AXUIElement queries, and global hotkeys. Distributed via Developer ID, not Mac App Store.
- **API keys in Keychain** — Never UserDefaults. Access via `KeychainHelper` with key `"deepgram_api_key"`.
- **`@unchecked Sendable`** — Used on `@Observable` classes that manage their own thread safety via `NSLock`.
- **AsyncStream everywhere** — Audio capture, transcription results, hotkey events, level monitoring, and noise warnings all flow through `AsyncStream`.
- **OSLog logging** — Use `Log.orchestrator`, `Log.transcription`, `Log.audio`, etc. from `ChitChatCore/Utilities/Logger.swift`.
- **NSLock deadlock risk** — Never call `continuation.finish()` inside a lock if `onTermination` also acquires the same lock. Extract the continuation first, then finish outside the lock.
- **Audio format** — AVAudioEngine captures Float32 PCM at 16kHz mono. `AudioFormatConverter.float32ToInt16()` converts for Deepgram's `linear16` encoding.
- **Menu bar app** — `LSUIElement=true` in Info.plist. `NSApp.setActivationPolicy(.accessory)`. No dock icon.
- **xcodegen** — Run `xcodegen generate` after adding/removing source files to regenerate the `.xcodeproj` from `project.yml`.

## Test Mocks

All service mocks are in `Tests/ChitChatCoreTests/Mocks/MockServices.swift`. `MockTranscriptionService.emitResult()` lets tests inject transcription results into the pipeline. `MockAccessibilityService.hasFocusedField` controls clipboard fallback behavior.
