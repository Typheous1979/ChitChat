import Foundation

@Observable
public final class SettingsManager {
    public var settings: AppSettings {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private static let settingsKey = "com.chitchat.settings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
    }

    public func update(_ mutation: (inout AppSettings) -> Void) {
        mutation(&settings)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
    }

    public func resetToDefaults() {
        settings = AppSettings()
    }
}
