import Foundation

/// Utilities for converting between audio formats.
public enum AudioFormatConverter {
    /// Convert Float32 PCM samples to Int16 PCM (linear16).
    /// Deepgram expects Int16 linear PCM for the `linear16` encoding.
    public static func float32ToInt16(_ float32Data: Data) -> Data {
        let sampleCount = float32Data.count / MemoryLayout<Float>.size
        var int16Data = Data(count: sampleCount * MemoryLayout<Int16>.size)

        float32Data.withUnsafeBytes { floatBuffer in
            int16Data.withUnsafeMutableBytes { int16Buffer in
                guard let floatPtr = floatBuffer.baseAddress?.assumingMemoryBound(to: Float.self),
                      let int16Ptr = int16Buffer.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }

                for i in 0..<sampleCount {
                    let clamped = max(-1.0, min(1.0, floatPtr[i]))
                    int16Ptr[i] = Int16(clamped * Float(Int16.max))
                }
            }
        }

        return int16Data
    }

    /// Convert Int16 PCM samples to Float32 PCM.
    public static func int16ToFloat32(_ int16Data: Data) -> Data {
        let sampleCount = int16Data.count / MemoryLayout<Int16>.size
        var float32Data = Data(count: sampleCount * MemoryLayout<Float>.size)

        int16Data.withUnsafeBytes { int16Buffer in
            float32Data.withUnsafeMutableBytes { floatBuffer in
                guard let int16Ptr = int16Buffer.baseAddress?.assumingMemoryBound(to: Int16.self),
                      let floatPtr = floatBuffer.baseAddress?.assumingMemoryBound(to: Float.self) else { return }

                for i in 0..<sampleCount {
                    floatPtr[i] = Float(int16Ptr[i]) / Float(Int16.max)
                }
            }
        }

        return float32Data
    }
}
