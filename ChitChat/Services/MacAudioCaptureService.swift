import AVFoundation
import CoreAudio
import ChitChatCore

final class MacAudioCaptureService: AudioCaptureService, @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var _selectedDevice: AudioDevice?
    private var _isCapturing = false
    private var tapRemoved = false
    private var levelEngine: AVAudioEngine?

    var selectedDevice: AudioDevice? {
        lock.withLock { _selectedDevice }
    }

    var isCapturing: Bool {
        lock.withLock { _isCapturing }
    }

    // MARK: - Device Enumeration

    func availableDevices() async -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }

        let defaultInputID = getDefaultInputDeviceID()

        return deviceIDs.compactMap { deviceID -> AudioDevice? in
            guard hasInputStreams(deviceID: deviceID) else { return nil }
            let name = getDeviceStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceNameCFString) ?? "Unknown"
            let manufacturer = getDeviceStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceManufacturerCFString) ?? ""
            let uid = getDeviceStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID) ?? "\(deviceID)"
            let sampleRate = getDeviceNominalSampleRate(deviceID: deviceID)
            let channels = getDeviceInputChannelCount(deviceID: deviceID)

            return AudioDevice(
                id: uid,
                name: name,
                manufacturer: manufacturer,
                sampleRate: sampleRate,
                channelCount: channels,
                isDefault: deviceID == defaultInputID
            )
        }
    }

    func selectDevice(_ device: AudioDevice?) async throws {
        lock.withLock { _selectedDevice = device }
    }

    // MARK: - Audio Capture

    func startCapture(sampleRate: Int, channels: Int) async throws -> AsyncStream<Data> {
        // Ensure microphone permission is granted before touching AVAudioEngine
        let micGranted = await requestMicrophoneAccess()
        guard micGranted else {
            throw AudioCaptureError.microphonePermissionDenied
        }

        let captureEngine = AVAudioEngine()
        lock.withLock { tapRemoved = false }

        if let device = selectedDevice {
            try setInputDevice(engine: captureEngine, deviceUID: device.id)
        }

        let inputNode = captureEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channels),
            interleaved: false
        )!

        // Start the engine BEFORE creating the AsyncStream so errors propagate properly
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard self != nil else { return }
            // Conversion happens inside the stream yield below
            _ = buffer // placeholder — actual yield is set up in the stream
        }

        // Remove the placeholder tap; we'll install the real one in the stream
        inputNode.removeTap(onBus: 0)

        do {
            try captureEngine.start()
        } catch {
            Log.audio.error("AVAudioEngine failed to start: \(error.localizedDescription)")
            throw AudioCaptureError.engineStartFailed(error.localizedDescription)
        }

        lock.withLock {
            self.engine = captureEngine
            self._isCapturing = true
        }

        return AsyncStream { continuation in
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
                guard let converter else {
                    if let channelData = buffer.floatChannelData?[0] {
                        let data = Data(bytes: channelData, count: Int(buffer.frameLength) * MemoryLayout<Float>.size)
                        continuation.yield(data)
                    }
                    return
                }

                let ratio = targetFormat.sampleRate / inputFormat.sampleRate
                let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else { return }

                var convError: NSError?
                var hasData = true
                converter.convert(to: outputBuffer, error: &convError) { _, outStatus in
                    if hasData {
                        hasData = false
                        outStatus.pointee = .haveData
                        return buffer
                    }
                    outStatus.pointee = .noDataNow
                    return nil
                }

                if convError == nil, let channelData = outputBuffer.floatChannelData?[0], outputBuffer.frameLength > 0 {
                    let data = Data(bytes: channelData, count: Int(outputBuffer.frameLength) * MemoryLayout<Float>.size)
                    continuation.yield(data)
                }
            }

            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock {
                    guard self?.tapRemoved == false else { return }
                    self?.tapRemoved = true
                    inputNode.removeTap(onBus: 0)
                    captureEngine.stop()
                    self?._isCapturing = false
                    self?.engine = nil
                }
            }
        }
    }

    func stopCapture() async {
        lock.withLock {
            guard !tapRemoved else { return }
            tapRemoved = true
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            engine = nil
            _isCapturing = false
        }
    }

    // MARK: - Level Monitoring

    func startLevelMonitoring() async throws -> AsyncStream<AudioLevelInfo> {
        let micGranted = await requestMicrophoneAccess()
        guard micGranted else {
            throw AudioCaptureError.microphonePermissionDenied
        }

        let monitorEngine = AVAudioEngine()

        if let device = selectedDevice {
            try setInputDevice(engine: monitorEngine, deviceUID: device.id)
        }

        let inputNode = monitorEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        do {
            try monitorEngine.start()
        } catch {
            throw AudioCaptureError.engineStartFailed(error.localizedDescription)
        }

        lock.withLock { self.levelEngine = monitorEngine }

        return AsyncStream { continuation in
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameCount = Int(buffer.frameLength)
                guard frameCount > 0 else { return }

                var sumOfSquares: Float = 0
                var peak: Float = 0

                for i in 0..<frameCount {
                    let sample = abs(channelData[i])
                    sumOfSquares += sample * sample
                    if sample > peak { peak = sample }
                }

                let rms = sqrt(sumOfSquares / Float(frameCount))
                let avgPowerDb = rms > 0 ? 20 * log10(rms) : -160
                let peakDb = peak > 0 ? 20 * log10(peak) : -160

                let info = AudioLevelInfo(
                    averagePower: avgPowerDb,
                    peakPower: peakDb,
                    rmsLevel: min(rms * 3.0, 1.0)
                )
                continuation.yield(info)
            }

            continuation.onTermination = { [weak self] _ in
                inputNode.removeTap(onBus: 0)
                monitorEngine.stop()
                self?.lock.withLock { self?.levelEngine = nil }
            }
        }
    }

    func stopLevelMonitoring() async {
        lock.withLock {
            levelEngine?.inputNode.removeTap(onBus: 0)
            levelEngine?.stop()
            levelEngine = nil
        }
    }

    // MARK: - Microphone Permission

    private func requestMicrophoneAccess() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            Log.audio.error("Microphone permission denied. Status: \(status.rawValue)")
            return false
        }
    }

    // MARK: - CoreAudio Helpers

    private func setInputDevice(engine: AVAudioEngine, deviceUID: String) throws {
        guard var resolvedID = getDeviceIDForUID(deviceUID) else {
            throw AudioCaptureError.deviceNotFound
        }

        let unit = engine.inputNode.audioUnit!
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &resolvedID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioCaptureError.deviceSelectionFailed
        }
    }

    private func getDeviceIDForUID(_ uid: String) -> AudioDeviceID? {
        let cfUID = uid as CFString
        let outputPointer = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<AudioDeviceID>.size, alignment: MemoryLayout<AudioDeviceID>.alignment)
        defer { outputPointer.deallocate() }

        var mutableCFUID = cfUID
        var translation = AudioValueTranslation(
            mInputData: &mutableCFUID,
            mInputDataSize: UInt32(MemoryLayout<CFString>.size),
            mOutputData: outputPointer,
            mOutputDataSize: UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDeviceForUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioValueTranslation>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &size,
            &translation
        )
        guard status == noErr else { return nil }
        return outputPointer.load(as: AudioDeviceID.self)
    }

    private func getDefaultInputDeviceID() -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &size, &deviceID)
        return deviceID
    }

    private func hasInputStreams(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &size)
        return status == noErr && size > 0
    }

    private func getDeviceStringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &value)
        return status == noErr ? value as String : nil
    }

    private func getDeviceNominalSampleRate(deviceID: AudioDeviceID) -> Double {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &sampleRate)
        return sampleRate
    }

    private func getDeviceInputChannelCount(deviceID: AudioDeviceID) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &size)
        guard status == noErr, size > 0 else { return 0 }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferListPointer.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, bufferListPointer)
        guard status == noErr else { return 0 }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

// MARK: - Errors

enum AudioCaptureError: Error, LocalizedError {
    case noInputDevice
    case deviceNotFound
    case deviceSelectionFailed
    case microphonePermissionDenied
    case engineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .noInputDevice: return "No audio input device available."
        case .deviceNotFound: return "Selected audio device not found."
        case .deviceSelectionFailed: return "Failed to select audio device."
        case .microphonePermissionDenied: return "Microphone permission is required. Please grant access in System Settings > Privacy & Security > Microphone."
        case .engineStartFailed(let detail): return "Audio engine failed to start: \(detail)"
        }
    }
}
