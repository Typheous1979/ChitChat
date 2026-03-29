import Foundation
import Testing
@testable import ChitChatCore

@Suite("NoiseFloorDetector Tests")
struct NoiseFloorDetectorTests {
    @Test("Does not warn on silence")
    func silenceNoWarning() async {
        let detector = NoiseFloorDetector(warningThresholdDb: -25, windowSize: 3)
        let stream = detector.startMonitoring()

        var warnings: [NoiseFloorDetector.NoiseWarning] = []

        // Start collecting in parallel task FIRST so stream initializes
        let collector = Task {
            for await warning in stream {
                warnings.append(warning)
            }
        }

        // Let the collector task start and the stream initialize
        try? await Task.sleep(for: .milliseconds(50))

        // Feed silent buffers
        let silence = Data(count: 512 * MemoryLayout<Float>.size)
        for _ in 0..<5 {
            detector.processBuffer(silence)
        }

        try? await Task.sleep(for: .milliseconds(50))
        detector.stopMonitoring()

        // Wait for collector with a timeout
        _ = await Task {
            await collector.value
        }.value

        #expect(warnings.isEmpty)
    }

    @Test("Warns on loud noise")
    func loudNoiseWarning() async {
        let detector = NoiseFloorDetector(warningThresholdDb: -25, windowSize: 2)
        let stream = detector.startMonitoring()

        var warnings: [NoiseFloorDetector.NoiseWarning] = []

        let collector = Task {
            for await warning in stream {
                warnings.append(warning)
            }
        }

        // Let the collector task start
        try? await Task.sleep(for: .milliseconds(50))

        // Feed loud buffers
        let sampleCount = 512
        var loudData = Data(count: sampleCount * MemoryLayout<Float>.size)
        loudData.withUnsafeMutableBytes { buf in
            let ptr = buf.baseAddress!.assumingMemoryBound(to: Float.self)
            for i in 0..<sampleCount { ptr[i] = 0.5 }
        }
        for _ in 0..<5 {
            detector.processBuffer(loudData)
        }

        try? await Task.sleep(for: .milliseconds(50))
        detector.stopMonitoring()
        await collector.value

        #expect(!warnings.isEmpty)
        #expect(warnings.first?.averageDb ?? -160 > -25)
    }
}
