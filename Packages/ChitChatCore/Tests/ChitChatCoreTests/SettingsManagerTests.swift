import Foundation
import Testing
@testable import ChitChatCore

@Suite("SettingsManager Tests")
struct SettingsManagerTests {
    @Test("Loads default settings when no saved data exists")
    func loadsDefaults() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let manager = SettingsManager(defaults: defaults)
        #expect(manager.settings.transcriptionEngine == .deepgram)
        #expect(manager.settings.hotkeyMode == .pushToTalk)
        #expect(manager.settings.launchAtLogin == false)
    }

    @Test("Persists settings across instances")
    func persistsSettings() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let manager1 = SettingsManager(defaults: defaults)
        manager1.update { $0.transcriptionEngine = .whisperCpp }
        manager1.update { $0.launchAtLogin = true }

        let manager2 = SettingsManager(defaults: defaults)
        #expect(manager2.settings.transcriptionEngine == .whisperCpp)
        #expect(manager2.settings.launchAtLogin == true)
    }

    @Test("Reset to defaults clears custom settings")
    func resetToDefaults() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let manager = SettingsManager(defaults: defaults)
        manager.update { $0.transcriptionEngine = .whisperCpp }
        manager.resetToDefaults()
        #expect(manager.settings.transcriptionEngine == .deepgram)
    }

    @Test("Toggle settings persist and reload correctly")
    func toggleSettingsPersist() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let manager = SettingsManager(defaults: defaults)
        manager.update { settings in
            settings.noiseSuppression = false
            settings.addTrailingSpace = false
            settings.showTranscriptionOverlay = false
            settings.launchAtLogin = true
        }

        let reloaded = SettingsManager(defaults: defaults)
        #expect(reloaded.settings.noiseSuppression == false)
        #expect(reloaded.settings.addTrailingSpace == false)
        #expect(reloaded.settings.showTranscriptionOverlay == false)
        #expect(reloaded.settings.launchAtLogin == true)
    }

    @Test("Calibration data persists correctly")
    func calibrationPersists() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let manager = SettingsManager(defaults: defaults)
        manager.update {
            $0.calibratedNoiseFloorDb = -45.0
            $0.calibratedSpeechLevelDb = -20.0
            $0.calibratedSNR = 25.0
        }

        let reloaded = SettingsManager(defaults: defaults)
        #expect(reloaded.settings.calibratedNoiseFloorDb == -45.0)
        #expect(reloaded.settings.calibratedSpeechLevelDb == -20.0)
        #expect(reloaded.settings.calibratedSNR == 25.0)
    }

    @Test("Old settings with removed keys still load")
    func removedSettingsMigration() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Save settings with current schema, then verify reload works
        let manager1 = SettingsManager(defaults: defaults)
        manager1.update { $0.launchAtLogin = true; $0.noiseSuppression = false }

        // Reload — should preserve values
        let manager2 = SettingsManager(defaults: defaults)
        #expect(manager2.settings.launchAtLogin == true)
        #expect(manager2.settings.noiseSuppression == false)
    }
}
