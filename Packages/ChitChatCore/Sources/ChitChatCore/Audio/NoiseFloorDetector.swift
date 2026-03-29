import Foundation

/// Continuously monitors background noise during recording sessions.
/// Emits warnings when noise exceeds acceptable thresholds.
public final class NoiseFloorDetector: @unchecked Sendable {
    private let warningThresholdDb: Float
    private let windowSize: Int
    private let lock = NSLock()
    private var recentLevels: [Float] = []
    private var continuation: AsyncStream<NoiseWarning>.Continuation?

    public struct NoiseWarning: Sendable {
        public let level: Float
        public let averageDb: Float
        public let message: String
    }

    /// - Parameters:
    ///   - warningThresholdDb: dB level above which a warning is emitted (default -25 dB)
    ///   - windowSize: number of recent samples to average (default 10)
    public init(warningThresholdDb: Float = -25, windowSize: Int = 10) {
        self.warningThresholdDb = warningThresholdDb
        self.windowSize = windowSize
    }

    /// Start monitoring. Returns a stream of noise warnings.
    public func startMonitoring() -> AsyncStream<NoiseWarning> {
        AsyncStream { continuation in
            self.lock.withLock {
                self.continuation = continuation
                self.recentLevels = []
            }
        }
    }

    /// Feed an audio buffer for analysis. Call this for each buffer during recording.
    public func processBuffer(_ buffer: Data) {
        let rms = computeRMS(from: buffer)
        let db = rms > 0 ? 20 * log10(rms) : -160.0

        // Compute average and check threshold under lock, then yield outside lock
        let warning: NoiseWarning? = lock.withLock {
            recentLevels.append(db)
            if recentLevels.count > windowSize {
                recentLevels.removeFirst()
            }

            let avgDb = recentLevels.reduce(0, +) / Float(recentLevels.count)

            if avgDb > warningThresholdDb {
                return NoiseWarning(
                    level: rms,
                    averageDb: avgDb,
                    message: "High background noise detected (\(Int(avgDb)) dB)"
                )
            }
            return nil
        }

        if let warning {
            lock.withLock { continuation }?.yield(warning)
        }
    }

    /// Stop monitoring.
    public func stopMonitoring() {
        // Extract continuation outside lock to avoid deadlock when finish() triggers onTermination
        let cont = lock.withLock { () -> AsyncStream<NoiseWarning>.Continuation? in
            let c = continuation
            continuation = nil
            recentLevels = []
            return c
        }
        cont?.finish()
    }

    private func computeRMS(from data: Data) -> Float {
        data.withUnsafeBytes { buffer -> Float in
            guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: Float.self) else { return 0 }
            let count = data.count / MemoryLayout<Float>.size
            guard count > 0 else { return 0 }
            var sum: Float = 0
            for i in 0..<count { sum += ptr[i] * ptr[i] }
            return sqrt(sum / Float(count))
        }
    }
}
