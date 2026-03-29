import Foundation
import os.log

/// Centralized logging using OSLog with subsystem and category support.
public enum Log {
    private static let subsystem = "com.justinkalicharan.chitchat"

    public static let audio = os.Logger(subsystem: subsystem, category: "audio")
    public static let transcription = os.Logger(subsystem: subsystem, category: "transcription")
    public static let injection = os.Logger(subsystem: subsystem, category: "injection")
    public static let hotkey = os.Logger(subsystem: subsystem, category: "hotkey")
    public static let orchestrator = os.Logger(subsystem: subsystem, category: "orchestrator")
    public static let training = os.Logger(subsystem: subsystem, category: "training")
    public static let settings = os.Logger(subsystem: subsystem, category: "settings")
    public static let general = os.Logger(subsystem: subsystem, category: "general")
}
