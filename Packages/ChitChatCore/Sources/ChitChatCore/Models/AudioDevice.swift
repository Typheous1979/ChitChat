import Foundation

public struct AudioDevice: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let name: String
    public let manufacturer: String
    public let sampleRate: Double
    public let channelCount: Int
    public let isDefault: Bool

    public init(id: String, name: String, manufacturer: String = "", sampleRate: Double = 44100, channelCount: Int = 1, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.isDefault = isDefault
    }
}

public struct AudioLevelInfo: Sendable {
    public let averagePower: Float
    public let peakPower: Float
    public let rmsLevel: Float

    public init(averagePower: Float, peakPower: Float, rmsLevel: Float) {
        self.averagePower = averagePower
        self.peakPower = peakPower
        self.rmsLevel = rmsLevel
    }

    public static let zero = AudioLevelInfo(averagePower: -160, peakPower: -160, rmsLevel: 0)
}
