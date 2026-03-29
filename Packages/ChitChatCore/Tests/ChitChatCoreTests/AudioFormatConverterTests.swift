import Foundation
import Testing
@testable import ChitChatCore

@Suite("AudioFormatConverter Tests")
struct AudioFormatConverterTests {
    @Test("Float32 to Int16 conversion preserves signal")
    func float32ToInt16() {
        // Create a simple sine-ish pattern: [0.0, 0.5, 1.0, -0.5, -1.0]
        let floats: [Float] = [0.0, 0.5, 1.0, -0.5, -1.0]
        var floatData = Data(count: floats.count * MemoryLayout<Float>.size)
        floatData.withUnsafeMutableBytes { buf in
            let ptr = buf.baseAddress!.assumingMemoryBound(to: Float.self)
            for (i, v) in floats.enumerated() { ptr[i] = v }
        }

        let int16Data = AudioFormatConverter.float32ToInt16(floatData)
        #expect(int16Data.count == floats.count * MemoryLayout<Int16>.size)

        let int16Values = int16Data.withUnsafeBytes { buf in
            Array(buf.bindMemory(to: Int16.self))
        }

        #expect(int16Values[0] == 0)
        #expect(int16Values[1] > 16000) // ~16383
        #expect(int16Values[2] == Int16.max)
        #expect(int16Values[3] < -16000)
        #expect(int16Values[4] == -Int16.max)
    }

    @Test("Round-trip conversion is approximately lossless")
    func roundTrip() {
        let original: [Float] = [0.0, 0.25, -0.25, 0.75, -0.75]
        var data = Data(count: original.count * MemoryLayout<Float>.size)
        data.withUnsafeMutableBytes { buf in
            let ptr = buf.baseAddress!.assumingMemoryBound(to: Float.self)
            for (i, v) in original.enumerated() { ptr[i] = v }
        }

        let int16 = AudioFormatConverter.float32ToInt16(data)
        let recovered = AudioFormatConverter.int16ToFloat32(int16)

        let recoveredFloats = recovered.withUnsafeBytes { buf in
            Array(buf.bindMemory(to: Float.self))
        }

        for (i, v) in original.enumerated() {
            let diff = abs(recoveredFloats[i] - v)
            #expect(diff < 0.001, "Sample \(i): expected ~\(v), got \(recoveredFloats[i])")
        }
    }
}
