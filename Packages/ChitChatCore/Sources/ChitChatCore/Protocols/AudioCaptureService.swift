import Foundation

/// Protocol for audio capture and microphone management.
public protocol AudioCaptureService: AnyObject, Sendable {
    /// List available input audio devices.
    func availableDevices() async -> [AudioDevice]

    /// Currently selected device (nil = system default).
    var selectedDevice: AudioDevice? { get }

    /// Select a specific input device. Pass nil for system default.
    func selectDevice(_ device: AudioDevice?) async throws

    /// Start capturing audio. Returns stream of raw PCM buffers (Float32, mono).
    func startCapture(sampleRate: Int, channels: Int) async throws -> AsyncStream<Data>

    /// Stop capturing audio.
    func stopCapture() async

    /// Whether audio is currently being captured.
    var isCapturing: Bool { get }

    /// Real-time audio level monitoring for meters.
    /// Can run independently of capture for setup/testing.
    func startLevelMonitoring() async throws -> AsyncStream<AudioLevelInfo>

    /// Stop level monitoring.
    func stopLevelMonitoring() async
}
