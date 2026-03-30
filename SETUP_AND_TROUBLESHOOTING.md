# Setup and Troubleshooting Guide

## Installing from Release (Recommended)

Download the latest `.dmg` from [GitHub Releases](https://github.com/Typheous1979/ChitChat/releases).

1. Open the DMG and drag **ChitChat** to **Applications**
2. Remove the quarantine flag (required for unsigned beta):
   ```bash
   xattr -cr /Applications/ChitChat.app
   ```
3. Launch ChitChat and grant Microphone and Accessibility permissions when prompted

### Terminal Install

```bash
curl -L https://github.com/Typheous1979/ChitChat/releases/download/v1.0.0-beta.3/ChitChat-1.0.0-beta.3.dmg -o /tmp/ChitChat.dmg && \
  hdiutil attach /tmp/ChitChat.dmg && \
  cp -R "/Volumes/ChitChat/ChitChat.app" /Applications/ && \
  hdiutil detach "/Volumes/ChitChat" && \
  rm /tmp/ChitChat.dmg && \
  xattr -cr /Applications/ChitChat.app && \
  open /Applications/ChitChat.app
```

## Building from Source

### Prerequisites

- **macOS 14.0 (Sonoma)** or later
- **Xcode 15+** with command-line tools installed
- A microphone (built-in or external)
- For Deepgram: an API key from [deepgram.com](https://deepgram.com)
- For Whisper: sufficient disk space for the model (75MB–3GB depending on size)

## Building the App

### Debug Build

```bash
xcodebuild -project ChitChat.xcodeproj -scheme ChitChat -configuration Debug build
```

### Release Build (Required for Whisper)

```bash
xcodebuild -project ChitChat.xcodeproj -scheme ChitChat -configuration Release build
```

> **Important:** Always use a Release build when using the Whisper engine. Debug builds compile whisper.cpp without compiler optimizations (`-O3`), making inference extremely slow (10x+ slower). If you see long delays after speaking, this is likely the cause.

### Running the App

After building, launch from the build output:

```bash
# Debug
open ~/Library/Developer/Xcode/DerivedData/ChitChat-*/Build/Products/Debug/ChitChat.app

# Release
open ~/Library/Developer/Xcode/DerivedData/ChitChat-*/Build/Products/Release/ChitChat.app
```

The app appears in the **menu bar** (not the dock). Look for the waveform icon.

### Building the Core Package Only

```bash
cd Packages/ChitChatCore && swift build
```

### Running Tests

```bash
# All tests (62 tests, 10 suites)
cd Packages/ChitChatCore && swift test

# Single test suite
cd Packages/ChitChatCore && swift test --filter DictationOrchestratorTests

# Single test
cd Packages/ChitChatCore && swift test --filter "Starts and stops dictation"
```

Tests use the **Swift Testing** framework (`@Test`, `#expect`, `@Suite`), not XCTest.

### Regenerating the Xcode Project

If you add or remove source files, regenerate the `.xcodeproj`:

```bash
xcodegen generate
```

This reads `project.yml` and produces a fresh `ChitChat.xcodeproj`.

## First-Run Setup

1. **Launch the app** — The onboarding wizard walks you through setup
2. **Grant Microphone permission** — macOS will prompt automatically
3. **Grant Accessibility permission** — Required for text injection
   - The app will prompt you to open System Settings
   - Navigate to **Privacy & Security > Accessibility**
   - Toggle **ChitChat** ON
4. **Choose a transcription engine:**
   - **Deepgram:** Enter your API key in Settings > Transcription
   - **Whisper:** Download a model in Settings > Transcription (Tiny or Base recommended to start)
5. **Set your hotkey** — Default is `Ctrl+Shift+Space`. Customize in Settings > General.

## Configuration

### Transcription Engine

Open Settings > Transcription to:
- Switch between Deepgram and Whisper
- Enter/update your Deepgram API key
- Download or delete Whisper models
- Choose Deepgram model variant and language

### Hotkey

Open Settings > General to:
- Record a new hotkey combination
- Switch between push-to-talk and toggle modes

### Audio

Open Settings > Audio to:
- Select your microphone
- Run an environment test (noise floor analysis)
- View real-time audio levels

### Overlay

The floating transcription overlay can be toggled in Settings > General under **"Show Transcription Overlay"**.

## Troubleshooting

### "Permission Required" warning persists

**Cause:** Accessibility permission was revoked. This happens every time the app is rebuilt because the code signature changes.

**Fix:** The app now **automatically resets** stale accessibility entries on startup and re-prompts. Just go to **System Settings > Privacy & Security > Accessibility** and toggle ChitChat ON. The warning should clear within 1 second (the app polls every second).

If the auto-reset doesn't work, you can manually reset:

```bash
tccutil reset Accessibility com.justinkalicharan.chitchat
```

### Text doesn't appear in the focused app

**Cause 1: Accessibility permission not granted**
- CGEvent posting to other apps requires accessibility permission
- Without it, keystrokes are silently dropped
- Check menu bar popover — if "Permissions required" warning is shown, grant accessibility permission

**Cause 2: The app doesn't have keyboard focus**
- Make sure you've clicked into the target app (Terminal, editor, browser, etc.) before pressing the hotkey
- ChitChat injects keystrokes into whatever app currently has keyboard focus

### Text doesn't appear in Terminal.app

ChitChat uses CGEvent Unicode keystrokes which work in Terminal.app, iTerm2, and other terminal emulators. If text isn't appearing:
- Verify accessibility permission is granted
- Ensure Terminal has keyboard focus when you press the hotkey
- Check the menu bar popover for recent transcriptions — if text appears there, the issue is with the target app, not transcription

### Background noise annotations appear in text

Whisper.cpp may emit annotations like `[MUSIC]`, `[BIRDS CHIRPING]`, or `[BLANK_AUDIO]`. These are automatically stripped by the noise token filter. If you see them, ensure you're running the latest build.

### "No Whisper model downloaded" error when pressing hotkey

**Cause:** You have Whisper (Offline) selected as your engine, but the selected model size isn't downloaded.

**Fix:** Open Settings > Transcription, check which model size is selected in the picker, and either:
- Download that model, or
- Switch to a model size you've already downloaded (look for the green checkmark)

### Whisper transcription is very slow

**Cause:** The app was built in Debug configuration. whisper.cpp runs without compiler optimizations in Debug.

**Fix:** Build in Release:

```bash
xcodebuild -project ChitChat.xcodeproj -scheme ChitChat -configuration Release build
```

Also consider using a smaller model (Tiny or Base) for faster inference.

### No transcription results at all

1. **Check microphone permission** — System Settings > Privacy & Security > Microphone > ChitChat must be ON
2. **Check engine configuration:**
   - Deepgram: Is the API key entered and valid? Use "Test Connection" in Settings.
   - Whisper: Is a model downloaded? Check Settings > Transcription.
3. **Check audio levels** — Open Settings > Audio and speak. The level meter should respond. If not, check your microphone selection.

### Hotkey doesn't work

1. **Check for conflicts** — Some key combinations are reserved by macOS (e.g., `Option+Space` for input sources)
2. **Try a different combination** — `Ctrl+Shift+Space` is the recommended default
3. **Verify the app is running** — Look for the waveform icon in the menu bar

### App doesn't appear after launch

ChitChat is a **menu bar app** — it has no dock icon and no main window. Look for the waveform icon in your menu bar (top-right area of the screen).

If you don't see it, check if it's hidden behind the notch or collapsed menu bar items. Try `Cmd+drag` to rearrange menu bar icons.

### Build fails after adding/removing files

Run `xcodegen generate` to regenerate the Xcode project from `project.yml`, then rebuild.

### Deepgram connection fails

1. Verify your API key is correct in Settings > Transcription
2. Check your internet connection
3. Use the "Test Connection" button in Settings to diagnose
4. Check that your Deepgram account has available credits

### Environment test stuck on Phase 1

**Cause:** Level monitoring is holding the microphone, preventing the audio capture stream from receiving buffers.

**Fix:** Close the Audio Settings tab before running the environment test. If the issue persists, restart the app and go directly to Voice Training > Test Audio Environment.

### Voice training recording captures no audio

**Cause:** Same mic contention issue — level monitoring or another capture session is active.

**Fix:** Ensure you're not actively dictating (hotkey recording) when training. Close Audio Settings if the level monitor is running.

### Noise gate too aggressive / filtering out speech

**Cause:** The environment test was run in a very quiet room, setting a low threshold. When you move to a noisier environment, the gate may be too tight.

**Fix:** Re-run the environment test in your current environment. The gate threshold adapts to the measured noise floor and SNR.

## Whisper Model Guide

| Model | Size | Speed | Accuracy | Recommended For |
|-------|------|-------|----------|-----------------|
| Tiny | 75 MB | Fastest | Good | Quick testing, low-powered machines |
| Base | 142 MB | Fast | Better | Daily use, good balance |
| Small | 466 MB | Moderate | Good | Better accuracy when speed isn't critical |
| Medium | 1.5 GB | Slow | Very Good | High-accuracy offline use |
| Large-v3 | 3 GB | Slowest | Best | Maximum accuracy, powerful hardware |

Models are stored in `~/Library/Application Support/ChitChat/Models/` and can be managed in Settings > Transcription.

## File Locations

| Item | Path |
|------|------|
| Whisper models | `~/Library/Application Support/ChitChat/Models/` |
| App settings | `~/Library/Application Support/ChitChat/settings.json` |
| Voice profiles | `~/Library/Application Support/ChitChat/VoiceProfiles/` |
| Noise gate calibration | UserDefaults (`calibratedNoiseFloorDb`, `calibratedSpeechLevelDb`, `calibratedSNR`) |
| Deepgram API key | macOS Keychain (key: `deepgram_api_key`) |
| Logs | Console.app, filter by `com.justinkalicharan.chitchat` |

## Viewing Logs

ChitChat uses Apple's OSLog framework. To view logs in real-time:

1. Open **Console.app**
2. Filter by process: `ChitChat`
3. Or filter by subsystem: `com.justinkalicharan.chitchat`

Log categories: `audio`, `transcription`, `injection`, `hotkey`, `orchestrator`, `training`, `settings`, `general`
