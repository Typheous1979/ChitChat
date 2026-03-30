import Foundation

// MARK: - App Settings

public struct AppSettings: Codable, Sendable {
    // General
    public var launchAtLogin: Bool = false

    // Hotkey
    public var hotkeyBinding: HotkeyBinding = .defaultBinding
    public var hotkeyMode: HotkeyMode = .pushToTalk

    // Transcription Engine
    public var transcriptionEngine: TranscriptionEngine = .deepgram
    public var deepgramModel: String = "nova-3"
    public var deepgramLanguage: String = "en"
    public var whisperModel: WhisperModelSize = .base
    public var whisperLanguage: String = "en"

    // Audio
    public var selectedMicrophoneId: String? = nil
    public var noiseSuppression: Bool = true

    // Audio Calibration (from environment test)
    public var calibratedNoiseFloorDb: Float? = nil
    public var calibratedSpeechLevelDb: Float? = nil
    public var calibratedSNR: Float? = nil

    // Advanced Features
    public var idleTalkReduction: Bool = false

    // Text Injection
    public var injectionMethod: InjectionMethod = .auto
    public var addTrailingSpace: Bool = true
    public var autoPunctuation: Bool = true
    public var autoCapitalization: Bool = true

    // Voice Training
    public var activeVoiceProfileId: UUID? = nil

    // UI
    public var maxRecentTranscriptions: Int = 20
    public var showTranscriptionOverlay: Bool = true
    public var overlayOpacity: Double = 0.9
    public var playFeedbackSounds: Bool = true

    public init() {}
}

// MARK: - Supporting Enums

public enum TranscriptionEngine: String, Codable, Sendable, CaseIterable {
    case deepgram = "deepgram"
    case whisperCpp = "whisper_cpp"

    public var displayName: String {
        switch self {
        case .deepgram: return "Deepgram"
        case .whisperCpp: return "Whisper (Offline)"
        }
    }
}

public enum HotkeyMode: String, Codable, Sendable, CaseIterable {
    case pushToTalk = "push_to_talk"
    case toggle = "toggle"

    public var displayName: String {
        switch self {
        case .pushToTalk: return "Push to Talk"
        case .toggle: return "Toggle"
        }
    }
}

public enum WhisperModelSize: String, Codable, Sendable, CaseIterable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case largeV3 = "large-v3"

    public var displayName: String {
        switch self {
        case .tiny: return "Tiny (75 MB)"
        case .base: return "Base (142 MB)"
        case .small: return "Small (466 MB)"
        case .medium: return "Medium (1.5 GB)"
        case .largeV3: return "Large V3 (3 GB)"
        }
    }
}

public enum InjectionMethod: String, Codable, Sendable, CaseIterable {
    case auto = "auto"
    case keyboard = "keyboard"
    case clipboard = "clipboard"

    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .keyboard: return "Keyboard Events"
        case .clipboard: return "Clipboard Paste"
        }
    }
}
