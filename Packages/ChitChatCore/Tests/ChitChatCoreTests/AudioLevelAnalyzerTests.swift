import Foundation
import Testing
@testable import ChitChatCore

@Suite("AudioLevelAnalyzer Tests")
struct AudioLevelAnalyzerTests {
    @Test("Analyzes silent buffer as very low level")
    func silentBuffer() {
        let analyzer = AudioLevelAnalyzer()
        let silence = Data(count: 1024 * MemoryLayout<Float>.size) // all zeros
        let level = analyzer.analyzeBuffer(silence)

        #expect(level.averagePower <= -100)
        #expect(level.peakPower <= -100)
        #expect(level.rmsLevel == 0)
    }

    @Test("Analyzes loud buffer as high level")
    func loudBuffer() {
        let analyzer = AudioLevelAnalyzer()
        let sampleCount = 1024
        var data = Data(count: sampleCount * MemoryLayout<Float>.size)
        data.withUnsafeMutableBytes { buf in
            let ptr = buf.baseAddress!.assumingMemoryBound(to: Float.self)
            for i in 0..<sampleCount {
                ptr[i] = 0.8 // loud signal
            }
        }

        let level = analyzer.analyzeBuffer(data)
        #expect(level.averagePower > -5)
        #expect(level.rmsLevel > 0.5)
    }

    @Test("Analyze buffer with mixed signal produces expected levels")
    func mixedSignalBuffer() {
        let analyzer = AudioLevelAnalyzer()
        let sampleCount = 1024
        var data = Data(count: sampleCount * MemoryLayout<Float>.size)
        data.withUnsafeMutableBytes { buf in
            let ptr = buf.baseAddress!.assumingMemoryBound(to: Float.self)
            for i in 0..<sampleCount {
                // Moderate sine wave
                ptr[i] = 0.3 * sin(Float(i) * 0.1)
            }
        }

        let level = analyzer.analyzeBuffer(data)
        // Should be a moderate level, not silent and not clipping
        #expect(level.averagePower > -20)
        #expect(level.averagePower < 0)
        #expect(level.rmsLevel > 0.1)
        #expect(level.rmsLevel < 1.0)
    }
}
