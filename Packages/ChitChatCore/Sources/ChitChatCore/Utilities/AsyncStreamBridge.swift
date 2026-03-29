import Foundation

/// Bridges a callback-based API into an AsyncStream.
///
/// Usage:
/// ```
/// let stream = AsyncStreamBridge<Data>.create { yield in
///     someCallbackAPI.onData { data in yield(data) }
/// }
/// ```
public enum AsyncStreamBridge<Element: Sendable> {
    public static func create(
        bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .bufferingNewest(64),
        setup: @escaping (AsyncStream<Element>.Continuation) -> Void
    ) -> AsyncStream<Element> {
        AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            setup(continuation)
        }
    }
}

/// Run an async operation with a timeout.
public func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError(seconds: seconds)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

public struct TimeoutError: Error, LocalizedError {
    public let seconds: TimeInterval
    public var errorDescription: String? {
        "Operation timed out after \(Int(seconds)) seconds."
    }
}
