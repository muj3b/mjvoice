import Foundation
import AppKit

enum ModelKind: String, Codable {
    case asr
    case noise
}

struct ModelDescriptor: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let provider: String
    let version: String
    let kind: ModelKind
    let downloadURL: URL
    let expectedFilename: String
    let sizeMB: Double
    let engineHint: String?
    let notes: String?

    init(id: String,
         name: String,
         provider: String,
         version: String,
         kind: ModelKind,
         downloadURL: URL,
         expectedFilename: String,
         sizeMB: Double,
         engineHint: String? = nil,
         notes: String? = nil) {
        self.id = id
        self.name = name
        self.provider = provider
        self.version = version
        self.kind = kind
        self.downloadURL = downloadURL
        self.expectedFilename = expectedFilename
        self.sizeMB = sizeMB
        self.engineHint = engineHint
        self.notes = notes
    }
}

struct InstalledModelRecord: Codable {
    let descriptor: ModelDescriptor
    let relativePath: String
    let installedAt: Date
    let isUserProvided: Bool
}

enum ModelManagerError: LocalizedError {
    case descriptorUnavailable
    case downloadInProgress
    case copyFailed
    case fileMissing

    var errorDescription: String? {
        switch self {
        case .descriptorUnavailable:
            return "The requested model could not be found."
        case .downloadInProgress:
            return "A download for this model is already in progress."
        case .copyFailed:
            return "Failed to place the downloaded model in the models directory."
        case .fileMissing:
            return "The installed model appears to be missing. Please re-download."
        }
    }
}

final class ModelManager: NSObject {
    static let shared = ModelManager()
    static let modelsDidChangeNotification = Notification.Name("ModelManagerModelsDidChange")

    struct DownloadHandle {
        fileprivate let taskIdentifier: Int
        public func cancel() {
            ModelManager.shared.cancelDownload(taskIdentifier)
        }
    }

    private struct DownloadContext {
        let descriptor: ModelDescriptor
        let progress: (Double) -> Void
        let completion: (Result<URL, Error>) -> Void
    }

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.mjvoice.model-manager", qos: .userInitiated)
    private let modelsDirectory: URL
    private let metadataURL: URL
    private lazy var session: URLSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    private var installedRecords: [String: InstalledModelRecord] = [:]
    private var activeDownloads: [Int: DownloadContext] = [:]

    override private init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        modelsDirectory = base.appendingPathComponent("mjvoice/Models", isDirectory: true)
        metadataURL = base.appendingPathComponent("mjvoice/models.json")
        super.init()
        do {
            try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        } catch {
            NSLog("[ModelManager] Failed to create models dir: \(error)")
        }
        loadMetadata()
    }

    // MARK: - Public API

    func installedModels(kind: ModelKind? = nil) -> [InstalledModelRecord] {
        queue.sync {
            installedRecords.values.filter { record in
                guard let kind else { return true }
                return record.descriptor.kind == kind
            }.sorted { $0.descriptor.name < $1.descriptor.name }
        }
    }

    func location(for descriptorID: String) -> URL? {
        queue.sync {
            guard let record = installedRecords[descriptorID] else { return nil }
            return modelsDirectory.appendingPathComponent(record.relativePath)
        }
    }

    struct ModelResolution {
        public let identifier: String
        public let url: URL?
        public let descriptor: ModelDescriptor?
    }

    func resolveASRModel(preferences: UserPreferences) -> ModelResolution {
        let preferredID = preferences.selectedASRModelID ?? defaultASRIdentifier(model: preferences.asrModel, size: preferences.modelSize)
        if let url = location(for: preferredID), let record = queue.sync(execute: { installedRecords[preferredID] }) {
            return ModelResolution(identifier: preferredID, url: url, descriptor: record.descriptor)
        }
        let descriptor = ModelCatalog.descriptor(for: preferences.asrModel, size: preferences.modelSize)
        return ModelResolution(identifier: preferredID, url: descriptor.flatMap { location(for: $0.id) }, descriptor: descriptor)
    }

    func resolveNoiseModel(preferences: UserPreferences) -> ModelResolution {
        let preferredID = preferences.selectedNoiseModelID ?? defaultNoiseIdentifier(model: preferences.noiseModel)
        if let url = location(for: preferredID), let record = queue.sync(execute: { installedRecords[preferredID] }) {
            return ModelResolution(identifier: preferredID, url: url, descriptor: record.descriptor)
        }
        let descriptor = ModelCatalog.noiseDescriptor(for: preferences.noiseModel)
        return ModelResolution(identifier: preferredID, url: descriptor.flatMap { location(for: $0.id) }, descriptor: descriptor)
    }

    @discardableResult
    func downloadDefaultModel(for asrModel: ASRModel, size: ModelSize, progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) -> DownloadHandle? {
        guard let descriptor = ModelCatalog.descriptor(for: asrModel, size: size) else {
            completion(.failure(ModelManagerError.descriptorUnavailable))
            return nil
        }
        return download(descriptor: descriptor, progress: progress, completion: completion)
    }

    @discardableResult
    func downloadDefaultNoiseModel(_ noise: NoiseModel, progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) -> DownloadHandle? {
        guard let descriptor = ModelCatalog.noiseDescriptor(for: noise) else {
            completion(.failure(ModelManagerError.descriptorUnavailable))
            return nil
        }
        return download(descriptor: descriptor, progress: progress, completion: completion)
    }

    @discardableResult
    func download(descriptor: ModelDescriptor, progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) -> DownloadHandle? {
        queue.sync {
            if let record = installedRecords[descriptor.id] {
                let fullURL = modelsDirectory.appendingPathComponent(record.relativePath)
                if fileManager.fileExists(atPath: fullURL.path) {
                    DispatchQueue.main.async { completion(.success(fullURL)) }
                    return nil
                }
            }

            if let existing = activeDownloads.first(where: { $0.value.descriptor.id == descriptor.id }) {
                DispatchQueue.main.async { completion(.failure(ModelManagerError.downloadInProgress)) }
                return DownloadHandle(taskIdentifier: existing.key)
            }

            let task = session.downloadTask(with: descriptor.downloadURL)
            activeDownloads[task.taskIdentifier] = DownloadContext(descriptor: descriptor, progress: progress, completion: completion)
            task.resume()
            return DownloadHandle(taskIdentifier: task.taskIdentifier)
        }
    }

    func registerCustomModel(from fileURL: URL, name: String, kind: ModelKind) throws -> InstalledModelRecord {
        let descriptor = ModelDescriptor(
            id: "custom-\(UUID().uuidString)",
            name: name,
            provider: "User",
            version: "1.0",
            kind: kind,
            downloadURL: fileURL,
            expectedFilename: fileURL.lastPathComponent,
            sizeMB: Double((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0) / 1_000_000.0,
            engineHint: nil,
            notes: "Imported manually"
        )
        let destination = modelsDirectory.appendingPathComponent(descriptor.expectedFilename)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: fileURL, to: destination)
        let record = InstalledModelRecord(descriptor: descriptor, relativePath: descriptor.expectedFilename, installedAt: Date(), isUserProvided: true)
        queue.sync {
            installedRecords[descriptor.id] = record
            persistMetadata()
        }
        return record
    }

    func deleteModel(id: String) {
        queue.sync {
            guard let record = installedRecords.removeValue(forKey: id) else { return }
            persistMetadata()
            let url = modelsDirectory.appendingPathComponent(record.relativePath)
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - Private helpers

    private func cancelDownload(_ identifier: Int) {
        queue.async {
            guard let context = self.activeDownloads.removeValue(forKey: identifier) else { return }
            self.session.getAllTasks { tasks in
                tasks.first { $0.taskIdentifier == identifier }?.cancel()
            }
            DispatchQueue.main.async {
                context.completion(.failure(NSError(domain: "com.mjvoice.model", code: -999, userInfo: [NSLocalizedDescriptionKey: "Download cancelled"])))
            }
        }
    }

    private func handleCompletion(for identifier: Int, result: Result<URL, Error>) {
        guard let context = queue.sync(execute: { activeDownloads.removeValue(forKey: identifier) }) else { return }
        DispatchQueue.main.async {
            context.completion(result)
        }
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL) else { return }
        do {
            let decoded = try JSONDecoder().decode([String: InstalledModelRecord].self, from: data)
            installedRecords = decoded
        } catch {
            NSLog("[ModelManager] Failed to decode metadata: \(error)")
        }
    }

    private func persistMetadata() {
        do {
            let data = try JSONEncoder().encode(installedRecords)
            try data.write(to: metadataURL, options: [.atomic])
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: ModelManager.modelsDidChangeNotification, object: nil)
            }
        } catch {
            NSLog("[ModelManager] Failed to write metadata: \(error)")
        }
    }

    private func defaultASRIdentifier(model: ASRModel, size: ModelSize) -> String {
        switch model {
        case .whisper:
            return "whisper-\(size.rawValue)"
        case .fluid:
            switch size {
            case .tiny: return "fluid-light"
            case .base: return "fluid-pro"
            case .small: return "fluid-advanced"
            }
        }
    }

    private func defaultNoiseIdentifier(model: NoiseModel) -> String {
        switch model {
        case .dtln_rs: return "dtln-rs"
        case .rnnoise: return "rnnoise"
        }
    }
}

extension ModelManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let context = queue.sync(execute: { activeDownloads[downloadTask.taskIdentifier] }) else { return }
        let destination = modelsDirectory.appendingPathComponent(context.descriptor.expectedFilename)
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)
            let record = InstalledModelRecord(descriptor: context.descriptor, relativePath: context.descriptor.expectedFilename, installedAt: Date(), isUserProvided: false)
            queue.sync {
                installedRecords[context.descriptor.id] = record
                persistMetadata()
            }
            handleCompletion(for: downloadTask.taskIdentifier, result: .success(destination))
        } catch {
            handleCompletion(for: downloadTask.taskIdentifier, result: .failure(ModelManagerError.copyFailed))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            handleCompletion(for: task.taskIdentifier, result: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let context = queue.sync(execute: { activeDownloads[downloadTask.taskIdentifier] }) else { return }
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        DispatchQueue.main.async {
            context.progress(progress)
        }
    }
}

private enum ModelCatalog {
    static func descriptor(for asr: ASRModel, size: ModelSize) -> ModelDescriptor? {
        switch asr {
        case .whisper:
            switch size {
            case .tiny:
                return ModelDescriptor(
                    id: "whisper-tiny",
                    name: "Whisper Tiny",
                    provider: "OpenAI",
                    version: "2025.01",
                    kind: .asr,
                    downloadURL: URL(string: "https://cdn.mjvoice.app/models/whisper/ggml-whisper-tiny.bin")!,
                    expectedFilename: "ggml-whisper-tiny.bin",
                    sizeMB: 75,
                    engineHint: "whisperkit",
                    notes: "Best for speed, lower accuracy"
                )
            case .base:
                return ModelDescriptor(
                    id: "whisper-base",
                    name: "Whisper Base",
                    provider: "OpenAI",
                    version: "2025.01",
                    kind: .asr,
                    downloadURL: URL(string: "https://cdn.mjvoice.app/models/whisper/ggml-whisper-base.bin")!,
                    expectedFilename: "ggml-whisper-base.bin",
                    sizeMB: 142,
                    engineHint: "whisperkit",
                    notes: "Balanced speed and accuracy"
                )
            case .small:
                return ModelDescriptor(
                    id: "whisper-small",
                    name: "Whisper Small",
                    provider: "OpenAI",
                    version: "2025.01",
                    kind: .asr,
                    downloadURL: URL(string: "https://cdn.mjvoice.app/models/whisper/ggml-whisper-small.bin")!,
                    expectedFilename: "ggml-whisper-small.bin",
                    sizeMB: 465,
                    engineHint: "whisperkit",
                    notes: "Highest accuracy offline"
                )
            }
        case .fluid:
            switch size {
            case .tiny:
                return ModelDescriptor(
                    id: "fluid-light",
                    name: "Fluid Audio Light",
                    provider: "Fluid",
                    version: "2025.01",
                    kind: .asr,
                    downloadURL: URL(string: "https://cdn.mjvoice.app/models/fluid/fluid-light-2025.onnx")!,
                    expectedFilename: "fluid-light.onnx",
                    sizeMB: 120,
                    engineHint: "fluid",
                    notes: "Optimized for low-latency multilingual dictation"
                )
            case .base:
                return ModelDescriptor(
                    id: "fluid-pro",
                    name: "Fluid Audio Pro",
                    provider: "Fluid",
                    version: "2025.01",
                    kind: .asr,
                    downloadURL: URL(string: "https://cdn.mjvoice.app/models/fluid/fluid-pro-2025.onnx")!,
                    expectedFilename: "fluid-pro.onnx",
                    sizeMB: 320,
                    engineHint: "fluid",
                    notes: "Balanced accuracy and latency"
                )
            case .small:
                return ModelDescriptor(
                    id: "fluid-advanced",
                    name: "Fluid Audio Advanced",
                    provider: "Fluid",
                    version: "2025.01",
                    kind: .asr,
                    downloadURL: URL(string: "https://cdn.mjvoice.app/models/fluid/fluid-advanced-2025.onnx")!,
                    expectedFilename: "fluid-advanced.onnx",
                    sizeMB: 540,
                    engineHint: "fluid",
                    notes: "Highest accuracy, more compute"
                )
            }
        }
    }

    static func noiseDescriptor(for noise: NoiseModel) -> ModelDescriptor? {
        switch noise {
        case .dtln_rs:
            return ModelDescriptor(
                id: "dtln-rs",
                name: "dtln-rs 2025",
                provider: "Datadog",
                version: "2025.02",
                kind: .noise,
                downloadURL: URL(string: "https://cdn.mjvoice.app/models/noise/dtln-rs-2025.tflite")!,
                expectedFilename: "dtln-rs-2025.tflite",
                sizeMB: 14,
                engineHint: "dtln",
                notes: "Rust accelerated dual-path noise suppression"
            )
        case .rnnoise:
            return ModelDescriptor(
                id: "rnnoise",
                name: "RNNoise Classic",
                provider: "Xiph",
                version: "2024.06",
                kind: .noise,
                downloadURL: URL(string: "https://cdn.mjvoice.app/models/noise/rnnoise-classic.bin")!,
                expectedFilename: "rnnoise-data.bin",
                sizeMB: 0.08,
                engineHint: "rnnoise",
                notes: "Lightweight baseline"
            )
        }
    }
}
