import Foundation
import Accelerate

/// A noise gate filter calibrated from environment test results.
/// Attenuates audio buffers whose RMS level is below the gate threshold,
/// effectively silencing background noise between speech segments.
///
/// The gate uses the calibrated noise floor + an offset to determine the threshold.
/// Buffers above the threshold pass through unchanged. Buffers below are zeroed out.
public final class AudioNoiseGate: Sendable {
    /// Gate threshold in linear amplitude (not dB).
    public let thresholdLinear: Float

    /// The noise floor from calibration, in dB.
    public let noiseFloorDb: Float

    /// dB offset above noise floor used for threshold.
    public let offsetDb: Float

    /// Create a noise gate from environment test calibration data.
    /// - Parameters:
    ///   - noiseFloorDb: Background noise level in dB (from environment test).
    ///   - snr: Signal-to-noise ratio in dB.
    ///   - offsetDb: dB above noise floor to set the gate threshold. Auto-calculated from SNR if nil.
    public init(noiseFloorDb: Float, snr: Float, offsetDb: Float? = nil) {
        self.noiseFloorDb = noiseFloorDb

        // Scale gate aggressiveness based on SNR:
        // Low SNR (noisy) → higher offset (more aggressive gating)
        // High SNR (quiet) → lower offset (gentle gating)
        let autoOffset: Float
        if snr < 10 {
            autoOffset = 8.0   // Very noisy — aggressive gate
        } else if snr < 20 {
            autoOffset = 5.0   // Moderate noise
        } else {
            autoOffset = 3.0   // Quiet environment — gentle gate
        }
        self.offsetDb = offsetDb ?? autoOffset

        // Convert threshold from dB to linear amplitude
        let thresholdDb = noiseFloorDb + self.offsetDb
        self.thresholdLinear = Self.dbToLinear(thresholdDb)
    }

    /// Process an audio buffer (Float32 PCM). Returns the buffer unchanged if
    /// its RMS exceeds the gate threshold, or a zeroed buffer if below (silence).
    public func process(_ buffer: Data) -> Data {
        let sampleCount = buffer.count / MemoryLayout<Float>.size
        guard sampleCount > 0 else { return buffer }

        let rms = computeRMS(buffer)

        // Gate open: speech detected — pass through unchanged
        if rms >= thresholdLinear {
            return buffer
        }

        // Gate closed: below threshold — return silence
        return Data(count: buffer.count)
    }

    /// Compute RMS (root-mean-square) amplitude of a Float32 PCM buffer using vDSP.
    public func computeRMS(_ buffer: Data) -> Float {
        let sampleCount = buffer.count / MemoryLayout<Float>.size
        guard sampleCount > 0 else { return 0 }

        return buffer.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: Float.self)
            var sumSquares: Float = 0
            vDSP_svesq(ptr.baseAddress!, 1, &sumSquares, vDSP_Length(sampleCount))
            return sqrt(sumSquares / Float(sampleCount))
        }
    }

    /// Convert dB value to linear amplitude.
    public static func dbToLinear(_ db: Float) -> Float {
        pow(10.0, db / 20.0)
    }

    /// Convert linear amplitude to dB.
    public static func linearToDb(_ linear: Float) -> Float {
        guard linear > 0 else { return -160 }
        return 20.0 * log10(linear)
    }
}
