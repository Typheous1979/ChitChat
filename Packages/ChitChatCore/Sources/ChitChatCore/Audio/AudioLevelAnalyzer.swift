import Foundation

// MARK: - Environment Test Result

public struct AudioEnvironmentReport: Sendable {
    public let noiseFloorDb: Float
    public let speechLevelDb: Float
    public let signalToNoiseRatio: Float
    public let peakLevel: Float
    public let clippingDetected: Bool
    public let recommendation: EnvironmentRecommendation

    public init(noiseFloorDb: Float, speechLevelDb: Float, signalToNoiseRatio: Float, peakLevel: Float, clippingDetected: Bool, recommendation: EnvironmentRecommendation) {
        self.noiseFloorDb = noiseFloorDb
        self.speechLevelDb = speechLevelDb
        self.signalToNoiseRatio = signalToNoiseRatio
        self.peakLevel = peakLevel
        self.clippingDetected = clippingDetected
        self.recommendation = recommendation
    }
}

public enum EnvironmentRecommendation: Sendable {
    case excellent(String)
    case good(String)
    case fair(String, suggestions: [String])
    case poor(String, suggestions: [String])

    public var label: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }

    public var message: String {
        switch self {
        case .excellent(let msg), .good(let msg): return msg
        case .fair(let msg, _), .poor(let msg, _): return msg
        }
    }

    public var suggestions: [String] {
        switch self {
        case .excellent, .good: return []
        case .fair(_, let suggestions), .poor(_, let suggestions): return suggestions
        }
    }
}

// MARK: - Audio Level Analyzer

/// Analyzes audio buffers for level, noise floor, and environment quality.
@Observable
public final class AudioLevelAnalyzer: @unchecked Sendable {
    public private(set) var currentLevel: AudioLevelInfo = .zero
    public private(set) var isAnalyzing: Bool = false

    private let lock = NSLock()

    public init() {}

    /// Run a two-phase environment test.
    /// Phase 1: Measure background noise (user silent) over `silenceDuration` seconds.
    /// Phase 2: Measure speech level (user reads prompt) over `speechDuration` seconds.
    public func runEnvironmentTest(
        audioStream: AsyncStream<Data>,
        silenceDuration: TimeInterval = 5.0,
        speechDuration: TimeInterval = 5.0,
        onPhaseChange: ((EnvironmentTestPhase) -> Void)? = nil
    ) async -> AudioEnvironmentReport {
        lock.withLock { isAnalyzing = true }
        defer { lock.withLock { isAnalyzing = false } }

        var silenceSamples: [Float] = []
        var speechSamples: [Float] = []

        let silenceStart = Date()
        let totalDuration = silenceDuration + speechDuration

        onPhaseChange?(.measuringNoise)

        for await buffer in audioStream {
            let elapsed = Date().timeIntervalSince(silenceStart)
            guard elapsed < totalDuration else { break }

            let rms = computeRMS(from: buffer)
            let peak = computePeak(from: buffer)

            if elapsed < silenceDuration {
                silenceSamples.append(rms)
                currentLevel = AudioLevelInfo(
                    averagePower: rms > 0 ? 20 * log10(rms) : -160,
                    peakPower: peak > 0 ? 20 * log10(peak) : -160,
                    rmsLevel: min(rms * 3.0, 1.0)
                )
            } else {
                if speechSamples.isEmpty {
                    onPhaseChange?(.measuringSpeech)
                }
                speechSamples.append(rms)
                currentLevel = AudioLevelInfo(
                    averagePower: rms > 0 ? 20 * log10(rms) : -160,
                    peakPower: peak > 0 ? 20 * log10(peak) : -160,
                    rmsLevel: min(rms * 3.0, 1.0)
                )
            }
        }

        onPhaseChange?(.complete)
        return buildReport(silenceSamples: silenceSamples, speechSamples: speechSamples)
    }

    /// Analyze a single buffer for level info (for real-time metering).
    public func analyzeBuffer(_ buffer: Data) -> AudioLevelInfo {
        let rms = computeRMS(from: buffer)
        let peak = computePeak(from: buffer)
        let avgDb = rms > 0 ? 20 * log10(rms) : -160.0
        let peakDb = peak > 0 ? 20 * log10(peak) : -160.0
        return AudioLevelInfo(averagePower: avgDb, peakPower: peakDb, rmsLevel: min(rms * 3.0, 1.0))
    }

    // MARK: - DSP

    private func computeRMS(from data: Data) -> Float {
        data.withUnsafeBytes { buffer -> Float in
            guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: Float.self) else { return 0 }
            let count = data.count / MemoryLayout<Float>.size
            guard count > 0 else { return 0 }
            var sum: Float = 0
            for i in 0..<count {
                sum += ptr[i] * ptr[i]
            }
            return sqrt(sum / Float(count))
        }
    }

    private func computePeak(from data: Data) -> Float {
        data.withUnsafeBytes { buffer -> Float in
            guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: Float.self) else { return 0 }
            let count = data.count / MemoryLayout<Float>.size
            var peak: Float = 0
            for i in 0..<count {
                let abs = Swift.abs(ptr[i])
                if abs > peak { peak = abs }
            }
            return peak
        }
    }

    // MARK: - Report Building

    private func buildReport(silenceSamples: [Float], speechSamples: [Float]) -> AudioEnvironmentReport {
        let noiseFloor = averageDb(silenceSamples)
        let speechLevel = averageDb(speechSamples)
        let snr = speechLevel - noiseFloor
        let peakLevel = speechSamples.max() ?? 0
        let clipping = peakLevel > 0.95

        let recommendation: EnvironmentRecommendation
        if snr >= 30 && !clipping && noiseFloor < -40 {
            recommendation = .excellent("Your environment is great for dictation.")
        } else if snr >= 20 && !clipping {
            recommendation = .good("Your environment is suitable for dictation.")
        } else if snr >= 10 {
            var suggestions: [String] = []
            if noiseFloor > -30 { suggestions.append("Try a quieter location or close windows/doors.") }
            if clipping { suggestions.append("Move further from the microphone to avoid clipping.") }
            recommendation = .fair("Dictation will work but accuracy may be reduced.", suggestions: suggestions)
        } else {
            var suggestions: [String] = []
            suggestions.append("Find a quieter environment.")
            if noiseFloor > -20 { suggestions.append("Background noise is very high.") }
            if speechLevel < -35 { suggestions.append("Speak louder or move closer to the microphone.") }
            if clipping { suggestions.append("Move further from the microphone.") }
            recommendation = .poor("Your environment may cause poor transcription accuracy.", suggestions: suggestions)
        }

        return AudioEnvironmentReport(
            noiseFloorDb: noiseFloor,
            speechLevelDb: speechLevel,
            signalToNoiseRatio: snr,
            peakLevel: peakLevel,
            clippingDetected: clipping,
            recommendation: recommendation
        )
    }

    private func averageDb(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -160 }
        let avg = samples.reduce(0, +) / Float(samples.count)
        return avg > 0 ? 20 * log10(avg) : -160
    }
}

// MARK: - Test Phase

public enum EnvironmentTestPhase: Sendable {
    case measuringNoise
    case measuringSpeech
    case complete
}
