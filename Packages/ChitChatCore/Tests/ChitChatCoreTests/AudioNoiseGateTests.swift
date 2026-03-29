import Foundation
import Testing
@testable import ChitChatCore

@Suite("AudioNoiseGate Tests")
struct AudioNoiseGateTests {

    // MARK: - Helpers

    /// Create a Float32 PCM buffer with a constant amplitude.
    private func makeBuffer(amplitude: Float, sampleCount: Int = 1024) -> Data {
        var samples = [Float](repeating: amplitude, count: sampleCount)
        return Data(bytes: &samples, count: sampleCount * MemoryLayout<Float>.size)
    }

    /// Create a sine wave buffer at a given amplitude.
    private func makeSineBuffer(amplitude: Float, frequency: Float = 440, sampleRate: Float = 16000, sampleCount: Int = 1024) -> Data {
        var samples = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            samples[i] = amplitude * sin(2.0 * .pi * frequency * Float(i) / sampleRate)
        }
        return Data(bytes: &samples, count: sampleCount * MemoryLayout<Float>.size)
    }

    // MARK: - Gate Threshold Tests

    @Test("Gate opens for speech-level audio")
    func gateOpensForSpeech() {
        // Noise floor at -40 dB, good SNR
        let gate = AudioNoiseGate(noiseFloorDb: -40, snr: 25)

        // Speech-level audio (amplitude ~0.1 = -20 dB, well above threshold)
        let speechBuffer = makeSineBuffer(amplitude: 0.1)
        let result = gate.process(speechBuffer)

        // Should pass through unchanged
        #expect(result == speechBuffer)
    }

    @Test("Gate closes for silence below threshold")
    func gateClosesForSilence() {
        // Noise floor at -40 dB, good SNR → threshold ~-37 dB
        let gate = AudioNoiseGate(noiseFloorDb: -40, snr: 25)

        // Very quiet audio (amplitude ~0.0001 = -80 dB, well below threshold)
        let silentBuffer = makeSineBuffer(amplitude: 0.0001)
        let result = gate.process(silentBuffer)

        // Should be zeroed out (silence)
        let rms = gate.computeRMS(result)
        #expect(rms == 0)
    }

    @Test("Gate closes for noise at floor level")
    func gateClosesForNoiseAtFloor() {
        // Noise floor at -30 dB, moderate SNR
        let gate = AudioNoiseGate(noiseFloorDb: -30, snr: 15)

        // Audio at exactly noise floor level (-30 dB = amplitude ~0.032)
        let noiseBuffer = makeSineBuffer(amplitude: 0.025)
        let result = gate.process(noiseBuffer)

        // Should be gated (below threshold which is floor + offset)
        let rms = gate.computeRMS(result)
        #expect(rms == 0)
    }

    @Test("Empty buffer passes through")
    func emptyBufferPassthrough() {
        let gate = AudioNoiseGate(noiseFloorDb: -40, snr: 20)
        let empty = Data()
        let result = gate.process(empty)
        #expect(result == empty)
    }

    // MARK: - Adaptive Threshold Tests

    @Test("Low SNR produces aggressive threshold")
    func lowSNRAggressiveGate() {
        // SNR < 10 → offset should be 8 dB
        let gate = AudioNoiseGate(noiseFloorDb: -30, snr: 5)
        #expect(gate.offsetDb == 8.0)
    }

    @Test("Moderate SNR produces medium threshold")
    func moderateSNRGate() {
        // 10 <= SNR < 20 → offset should be 5 dB
        let gate = AudioNoiseGate(noiseFloorDb: -35, snr: 15)
        #expect(gate.offsetDb == 5.0)
    }

    @Test("High SNR produces gentle threshold")
    func highSNRGentleGate() {
        // SNR >= 20 → offset should be 3 dB
        let gate = AudioNoiseGate(noiseFloorDb: -45, snr: 30)
        #expect(gate.offsetDb == 3.0)
    }

    @Test("Custom offset overrides auto-calculation")
    func customOffset() {
        let gate = AudioNoiseGate(noiseFloorDb: -40, snr: 25, offsetDb: 10.0)
        #expect(gate.offsetDb == 10.0)
    }

    // MARK: - dB Conversion Tests

    @Test("dB to linear conversion")
    func dbToLinear() {
        // 0 dB = 1.0, -20 dB = 0.1, -40 dB = 0.01
        #expect(abs(AudioNoiseGate.dbToLinear(0) - 1.0) < 0.001)
        #expect(abs(AudioNoiseGate.dbToLinear(-20) - 0.1) < 0.001)
        #expect(abs(AudioNoiseGate.dbToLinear(-40) - 0.01) < 0.001)
    }

    @Test("Linear to dB conversion")
    func linearToDb() {
        #expect(abs(AudioNoiseGate.linearToDb(1.0) - 0) < 0.1)
        #expect(abs(AudioNoiseGate.linearToDb(0.1) - (-20)) < 0.1)
        #expect(AudioNoiseGate.linearToDb(0) == -160)
    }

    // MARK: - RMS Tests

    @Test("RMS of constant signal equals amplitude")
    func rmsConstantSignal() {
        let gate = AudioNoiseGate(noiseFloorDb: -40, snr: 20)
        let buffer = makeBuffer(amplitude: 0.5, sampleCount: 256)
        let rms = gate.computeRMS(buffer)
        #expect(abs(rms - 0.5) < 0.001)
    }

    @Test("RMS of silence is zero")
    func rmsSilence() {
        let gate = AudioNoiseGate(noiseFloorDb: -40, snr: 20)
        let buffer = makeBuffer(amplitude: 0, sampleCount: 256)
        let rms = gate.computeRMS(buffer)
        #expect(rms == 0)
    }
}
