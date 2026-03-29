import Foundation

/// Manages downloading, storage, and deletion of Whisper GGML model files.
/// Models are stored in ~/Library/Application Support/ChitChat/Models/
@Observable
public final class WhisperModelManager: NSObject, @unchecked Sendable {
    public private(set) var downloadProgress: Double = 0
    public private(set) var isDownloading = false
    public private(set) var downloadError: String?
    public private(set) var currentDownloadModel: WhisperModelSize?

    /// Incremented on model download/delete so SwiftUI views that read it re-render.
    public private(set) var modelChangeCount: Int = 0

    private let lock = NSLock()
    private var downloadTask: URLSessionDownloadTask?
    private var downloadContinuation: CheckedContinuation<URL, Error>?
    @ObservationIgnored
    private var _session: URLSession?
    private var session: URLSession {
        if let s = _session { return s }
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        _session = s
        return s
    }

    public override init() {
        super.init()
    }

    // MARK: - Model Directory

    public static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ChitChat/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Full path for a given model size.
    public static func modelPath(for model: WhisperModelSize) -> URL {
        modelsDirectory.appendingPathComponent("ggml-\(model.rawValue).bin")
    }

    /// Check if a model file exists on disk.
    public func isModelDownloaded(_ model: WhisperModelSize) -> Bool {
        FileManager.default.fileExists(atPath: Self.modelPath(for: model).path)
    }

    /// Size of the downloaded model file in bytes, or nil if not downloaded.
    public func downloadedModelSize(_ model: WhisperModelSize) -> Int64? {
        let path = Self.modelPath(for: model)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path) else { return nil }
        return attrs[.size] as? Int64
    }

    /// List all downloaded models.
    public func downloadedModels() -> [WhisperModelSize] {
        WhisperModelSize.allCases.filter { isModelDownloaded($0) }
    }

    // MARK: - Download

    /// Download a Whisper GGML model from Hugging Face.
    public func downloadModel(_ model: WhisperModelSize) async throws {
        guard !isDownloading else {
            throw WhisperModelError.downloadAlreadyInProgress
        }

        let url = Self.downloadURL(for: model)
        let destination = Self.modelPath(for: model)

        lock.withLock {
            isDownloading = true
            downloadProgress = 0
            downloadError = nil
            currentDownloadModel = model
        }

        Log.transcription.info("Downloading Whisper model: \(model.rawValue) from \(url.absoluteString, privacy: .public)")

        do {
            let tempURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                self.lock.withLock { self.downloadContinuation = continuation }
                let task = self.session.downloadTask(with: url)
                self.lock.withLock { self.downloadTask = task }
                task.resume()
            }

            // Ensure the models directory exists before moving
            let modelsDir = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

            // Move from temp to final destination
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)

            Log.transcription.info("Whisper model \(model.rawValue) downloaded to \(destination.path, privacy: .public)")

            lock.withLock {
                isDownloading = false
                downloadProgress = 1.0
                currentDownloadModel = nil
                modelChangeCount += 1
            }
        } catch {
            Log.transcription.error("Whisper model download failed: \(error.localizedDescription, privacy: .public)")
            lock.withLock {
                isDownloading = false
                downloadError = error.localizedDescription
                currentDownloadModel = nil
            }
            throw error
        }
    }

    /// Cancel an in-progress download.
    public func cancelDownload() {
        lock.withLock {
            downloadTask?.cancel()
            downloadTask = nil
            isDownloading = false
            currentDownloadModel = nil
        }
    }

    // MARK: - Delete

    /// Delete a downloaded model from disk.
    public func deleteModel(_ model: WhisperModelSize) throws {
        let path = Self.modelPath(for: model)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
            Log.transcription.info("Deleted Whisper model: \(model.rawValue)")
            lock.withLock { modelChangeCount += 1 }
        }
    }

    // MARK: - Download URLs

    /// Hugging Face hosted GGML model files.
    static func downloadURL(for model: WhisperModelSize) -> URL {
        let base = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
        let filename: String
        switch model {
        case .tiny: filename = "ggml-tiny.bin"
        case .base: filename = "ggml-base.bin"
        case .small: filename = "ggml-small.bin"
        case .medium: filename = "ggml-medium.bin"
        case .largeV3: filename = "ggml-large-v3.bin"
        }
        return URL(string: "\(base)/\(filename)")!
    }
}

// MARK: - URLSessionDownloadDelegate

extension WhisperModelManager: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The file at `location` is deleted when this callback returns,
        // so copy it to a stable temp path before resuming the continuation.
        let stableTmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin")
        do {
            try FileManager.default.copyItem(at: location, to: stableTmp)
        } catch {
            lock.withLock {
                downloadContinuation?.resume(throwing: error)
                downloadContinuation = nil
            }
            return
        }
        lock.withLock {
            downloadContinuation?.resume(returning: stableTmp)
            downloadContinuation = nil
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        lock.withLock {
            downloadContinuation?.resume(throwing: error)
            downloadContinuation = nil
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        lock.withLock {
            self.downloadProgress = progress
        }
    }
}

// MARK: - Errors

public enum WhisperModelError: Error, LocalizedError {
    case downloadAlreadyInProgress
    case modelNotFound

    public var errorDescription: String? {
        switch self {
        case .downloadAlreadyInProgress: return "A model download is already in progress."
        case .modelNotFound: return "Model file not found on disk."
        }
    }
}
