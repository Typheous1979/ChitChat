# ChitChat

A native macOS menu bar app that transcribes your voice and injects text directly into any focused application. Press a hotkey, speak, release — your words appear wherever your cursor is.

## Features

- **Universal text injection** — Works in any app: Terminal, browsers, editors, Slack, and more via CGEvent keystrokes. No copy-paste needed.
- **Dual transcription engines**
  - **Deepgram Nova-3** — Cloud-based, real-time streaming with sub-second latency
  - **Whisper (Offline)** — Fully local inference via whisper.cpp. No internet required. Your audio never leaves your machine. Model cached for instant subsequent sessions.
- **Push-to-talk & toggle modes** — Hold the hotkey to dictate, or toggle on/off with a single press. Mode can be changed at any time.
- **Smart noise filtering** — Automatically strips whisper.cpp annotations like `[MUSIC]`, `[BIRDS CHIRPING]`, `[BLANK_AUDIO]` so only your speech appears.
- **Live transcription overlay** — Optional floating window shows what's being transcribed in real-time.
- **Incremental injection** — Partial results appear as you speak, replacing in-place as transcription refines.
- **Active model indicator** — Menu bar and settings show which engine/model is active and whether it's ready.
- **Menu bar app** — Lives in your menu bar. No dock icon, no window clutter.
- **Configurable hotkeys** — Set any key combination that works for your workflow.
- **Audio environment testing** — Built-in tool to analyze your microphone setup and background noise.
- **Automatic permission management** — Auto-detects and resets stale accessibility permissions after rebuilds.

## Requirements

- macOS 14.0 (Sonoma) or later
- Microphone access
- Accessibility permission (for text injection into other apps)
- Deepgram API key (for cloud transcription) or a downloaded Whisper model (for offline)

## Quick Start

1. **Build and run** the app (see [Setup Guide](SETUP_AND_TROUBLESHOOTING.md))
2. **Grant permissions** when prompted — Microphone and Accessibility
3. **Configure a transcription engine** in Settings:
   - For Deepgram: enter your API key
   - For Whisper: download a model (Tiny recommended to start)
4. **Click into any text field**, press your hotkey (default: `Ctrl+Shift+Space`), speak, then release
5. Your words appear in the text field

## Project Structure

```
ChitChat/
├── ChitChat/                   # macOS app target
│   ├── App/                    # AppDelegate, AppState, ChitChatApp
│   ├── Services/               # Platform implementations (Mac*)
│   ├── UI/                     # SwiftUI views
│   │   ├── MenuBar/            # Status bar + popover
│   │   ├── Overlay/            # Floating transcription window
│   │   ├── Settings/           # Settings tabs
│   │   ├── Onboarding/         # First-run setup wizard
│   │   └── Components/         # Reusable UI components
│   └── Platform/               # ServiceContainer, PlatformCapabilities
├── Packages/ChitChatCore/      # Platform-agnostic SPM package
│   ├── Sources/ChitChatCore/
│   │   ├── Protocols/          # Service protocol definitions
│   │   ├── Models/             # Data models & enums
│   │   ├── Orchestration/      # DictationOrchestrator
│   │   ├── Transcription/      # Deepgram, Whisper, Coordinator
│   │   ├── Audio/              # Format conversion, level analysis
│   │   ├── VoiceTraining/      # Profile store, training manager
│   │   ├── Settings/           # SettingsManager, KeychainHelper
│   │   └── Utilities/          # Logger, AsyncStreamBridge
│   └── Tests/ChitChatCoreTests/
├── project.yml                 # xcodegen project definition
└── CLAUDE.md                   # AI assistant instructions
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed design documentation.

## Building

```bash
# Debug build
xcodebuild -project ChitChat.xcodeproj -scheme ChitChat -configuration Debug build

# Release build (required for Whisper performance)
xcodebuild -project ChitChat.xcodeproj -scheme ChitChat -configuration Release build

# Run tests (27 tests, 8 suites)
cd Packages/ChitChatCore && swift test
```

See the full [Setup and Troubleshooting Guide](SETUP_AND_TROUBLESHOOTING.md) for detailed instructions.

## Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | This file — overview and quick start |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Detailed system design and data flows |
| [SETUP_AND_TROUBLESHOOTING.md](SETUP_AND_TROUBLESHOOTING.md) | Build instructions, configuration, and common issues |
| [CLAUDE.md](CLAUDE.md) | AI assistant context for Claude Code |

## Tech Stack

- **Swift 5.9+** / macOS 14+
- **SwiftUI + AppKit** hybrid UI
- **Swift Package Manager** for ChitChatCore module
- **SwiftWhisper** (whisper.cpp) for offline transcription
- **Deepgram WebSocket API** for cloud transcription
- **CGEvent** for keystroke injection
- **Carbon** for global hotkey registration
- **AXUIElement** for accessibility queries
- **AVAudioEngine + CoreAudio** for audio capture
- **Swift Testing** framework for unit tests

## License

All rights reserved. This project is not currently open-source licensed.
