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
    let components: [ModelComponent]?

    init(id: String,
         name: String,
         provider: String,
         version: String,
         kind: ModelKind,
         downloadURL: URL,
         expectedFilename: String,
         sizeMB: Double,
         engineHint: String? = nil,
         notes: String? = nil,
         components: [ModelComponent]? = nil) {
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
        self.components = components
    }
}

struct ModelComponent: Codable, Hashable {
    let filename: String
    let downloadURL: URL
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

final class ModelManager: NSObject, @unchecked Sendable {
    static let shared = ModelManager()
    static let modelsDidChangeNotification = Notification.Name("ModelManagerModelsDidChange")

    struct DownloadHandle {
        fileprivate let descriptorID: String
        public func cancel() {
            ModelManager.shared.cancelDownload(descriptorID)
        }
    }

    private final class DownloadContext {
        let descriptor: ModelDescriptor
        let progress: (Double) -> Void
        let completion: (Result<URL, Error>) -> Void
        let components: [ModelComponent]
        var currentIndex: Int = 0
        let destinationURL: URL
        let relativePath: String
        var currentBytesWritten: Int64 = 0
        var currentBytesExpected: Int64 = 0
        var totalComponentCount: Int { components.count }
        var triedMirror: Bool = false

        init(descriptor: ModelDescriptor,
             components: [ModelComponent],
             destinationURL: URL,
             relativePath: String,
             progress: @escaping (Double) -> Void,
             completion: @escaping (Result<URL, Error>) -> Void) {
            self.descriptor = descriptor
            self.components = components
            self.destinationURL = destinationURL
            self.relativePath = relativePath
            self.progress = progress
            self.completion = completion
        }
    }

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.mjvoice.model-manager", qos: .userInitiated)
    private let modelsDirectory: URL
    private let metadataURL: URL
    private let bundledNoiseResources: [String: (name: String, ext: String, subdirectory: String)] = [
        "dtln-rs": ("dtln-rs-2025", "tflite", "BundledModels"),
        "rnnoise": ("rnnoise-classic", "bin", "BundledModels")
    ]
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

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
        if let bundledURL = installBundledNoiseIfAvailable(for: descriptor) {
            DispatchQueue.main.async {
                progress(1.0)
                completion(.success(bundledURL))
            }
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

            if let _ = activeDownloads.first(where: { $0.value.descriptor.id == descriptor.id }) {
                DispatchQueue.main.async { completion(.failure(ModelManagerError.downloadInProgress)) }
                return DownloadHandle(descriptorID: descriptor.id)
            }

            let components = descriptor.components ?? [ModelComponent(filename: descriptor.expectedFilename, downloadURL: descriptor.downloadURL)]
            guard !components.isEmpty else {
                DispatchQueue.main.async { completion(.failure(ModelManagerError.descriptorUnavailable)) }
                return nil
            }

            let isSingleFile = components.count == 1 && descriptor.components == nil
            let destination: URL
            let relativePath: String
            if isSingleFile {
                destination = modelsDirectory.appendingPathComponent(descriptor.expectedFilename)
                relativePath = descriptor.expectedFilename
            } else {
                destination = modelsDirectory.appendingPathComponent(descriptor.id, isDirectory: true)
                relativePath = descriptor.id
            }

            do {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                if !isSingleFile {
                    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(ModelManagerError.copyFailed)) }
                return nil
            }

            let context = DownloadContext(descriptor: descriptor,
                                          components: components,
                                          destinationURL: destination,
                                          relativePath: relativePath,
                                          progress: progress,
                                          completion: completion)
            if startComponentDownload(context: context) {
                return DownloadHandle(descriptorID: descriptor.id)
            } else {
                DispatchQueue.main.async { completion(.failure(ModelManagerError.copyFailed)) }
                return nil
            }
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

    private func cancelDownload(_ descriptorID: String) {
        queue.async {
            guard let entry = self.activeDownloads.first(where: { $0.value.descriptor.id == descriptorID }) else { return }
            let taskIdentifier = entry.key
            let context = entry.value
            self.activeDownloads.removeValue(forKey: taskIdentifier)
            self.session.getAllTasks { tasks in
                tasks.first { $0.taskIdentifier == taskIdentifier }?.cancel()
            }
            DispatchQueue.main.async {
                context.completion(.failure(NSError(domain: "com.mjvoice.model", code: -999, userInfo: [NSLocalizedDescriptionKey: "Download cancelled"])))
            }
        }
    }

    @discardableResult
    private func startComponentDownload(context: DownloadContext) -> Bool {
        guard context.currentIndex < context.components.count else { return false }
        let component = context.components[context.currentIndex]
        context.currentBytesWritten = 0
        context.currentBytesExpected = 0
        let task = session.downloadTask(with: component.downloadURL)
        activeDownloads[task.taskIdentifier] = context
        task.resume()
        return true
    }

    private func updateProgress(for context: DownloadContext) {
        let completed = Double(context.currentIndex)
        let total = Double(context.totalComponentCount)
        let componentProgress: Double
        if context.currentBytesExpected > 0 {
            componentProgress = Double(context.currentBytesWritten) / Double(context.currentBytesExpected)
        } else {
            componentProgress = 0
        }
        let overall = total == 0 ? 0 : min(1.0, (completed + componentProgress) / total)
        DispatchQueue.main.async {
            context.progress(overall)
        }
    }

    private func finalize(context: DownloadContext, result: Result<URL, Error>) {
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

    @discardableResult
    private func installBundledNoiseIfAvailable(for descriptor: ModelDescriptor) -> URL? {
        guard let bundleInfo = bundledNoiseResources[descriptor.id],
              let resourceURL = Bundle.main.url(forResource: bundleInfo.name,
                                                withExtension: bundleInfo.ext,
                                                subdirectory: bundleInfo.subdirectory) else {
            return nil
        }
        let destination = modelsDirectory.appendingPathComponent(descriptor.expectedFilename)
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: resourceURL, to: destination)
            let record = InstalledModelRecord(descriptor: descriptor,
                                              relativePath: descriptor.expectedFilename,
                                              installedAt: Date(),
                                              isUserProvided: false)
            queue.sync {
                installedRecords[descriptor.id] = record
                persistMetadata()
            }
            return destination
        } catch {
            NSLog("[ModelManager] Failed to install bundled noise model: \(error)")
            return nil
        }
    }
    
    private func mirrorURL(for url: URL) -> URL? {
        // Simple mirror for Hugging Face URLs
        guard url.host?.contains("huggingface.co") == true else { return nil }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.host = "hf-mirror.com"
        return comps?.url
    }
}

extension ModelManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let context = queue.sync(execute: { activeDownloads.removeValue(forKey: downloadTask.taskIdentifier) }) else { return }
        let component = context.components[context.currentIndex]
        let targetURL: URL
        if context.totalComponentCount == 1 && context.descriptor.components == nil {
            targetURL = context.destinationURL
        } else {
            targetURL = context.destinationURL.appendingPathComponent(component.filename)
        }

        do {
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.moveItem(at: location, to: targetURL)
        } catch {
            finalize(context: context, result: .failure(ModelManagerError.copyFailed))
            return
        }

        context.currentIndex += 1
        updateProgress(for: context)

        if context.currentIndex >= context.totalComponentCount {
            let record = InstalledModelRecord(descriptor: context.descriptor,
                                              relativePath: context.relativePath,
                                              installedAt: Date(),
                                              isUserProvided: false)
            queue.sync {
                installedRecords[context.descriptor.id] = record
                persistMetadata()
            }
            DispatchQueue.main.async { context.progress(1.0) }
            finalize(context: context, result: .success(context.destinationURL))
        } else {
            queue.async {
                _ = self.startComponentDownload(context: context)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            if let context = queue.sync(execute: { activeDownloads.removeValue(forKey: task.taskIdentifier) }) {
                if let original = (task.originalRequest?.url) {
                    if !context.triedMirror, let alt = mirrorURL(for: original) {
                        // Retry this component with the mirror
                        context.triedMirror = true
                        let newTask = self.session.downloadTask(with: alt)
                        self.queue.sync { self.activeDownloads[newTask.taskIdentifier] = context }
                        newTask.resume()
                        return
                    }
                }
                finalize(context: context, result: .failure(error))
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let context = queue.sync(execute: { activeDownloads[downloadTask.taskIdentifier] }) else { return }
        context.currentBytesWritten = totalBytesWritten
        context.currentBytesExpected = totalBytesExpectedToWrite
        updateProgress(for: context)
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
                    downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin?download=1")!,
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
                    downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin?download=1")!,
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
                    downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin?download=1")!,
                    expectedFilename: "ggml-whisper-small.bin",
                    sizeMB: 465,
                    engineHint: "whisperkit",
                    notes: "Highest accuracy offline"
                )
            }
        case .fluid:
            switch size {
            case .tiny:
                let components = ModelCatalog.fluidComponents(repo: "Systran/faster-whisper-tiny")
                return ModelDescriptor(
                    id: "fluid-light",
                    name: "Fluid Audio Light",
                    provider: "Fluid",
                    version: "2025.01",
                    kind: .asr,
                    downloadURL: components[0].downloadURL,
                    expectedFilename: "fluid-light",
                    sizeMB: 120,
                    engineHint: "fluid",
                    notes: "Optimized for low-latency multilingual dictation",
                    components: components
                )
            case .base:
                let components = ModelCatalog.fluidComponents(repo: "Systran/faster-whisper-base")
                return ModelDescriptor(
                    id: "fluid-pro",
                    name: "Fluid Audio Pro",
                    provider: "Fluid",
                    version: "2025.01",
                    kind: .asr,
                    downloadURL: components[0].downloadURL,
                    expectedFilename: "fluid-pro",
                    sizeMB: 320,
                    engineHint: "fluid",
                    notes: "Balanced accuracy and latency",
                    components: components
                )
            case .small:
                let components = ModelCatalog.fluidComponents(repo: "Systran/faster-whisper-small")
                return ModelDescriptor(
                    id: "fluid-advanced",
                    name: "Fluid Audio Advanced",
                    provider: "Fluid",
                    version: "2025.01",
                    kind: .asr,
                    downloadURL: components[0].downloadURL,
                    expectedFilename: "fluid-advanced",
                    sizeMB: 540,
                    engineHint: "fluid",
                    notes: "Highest accuracy, more compute",
                    components: components
                )
            }
        }
    }

    private static func fluidComponents(repo: String) -> [ModelComponent] {
        let base = "https://huggingface.co/\(repo)/resolve/main"
        return [
            ModelComponent(filename: "config.json", downloadURL: URL(string: "\(base)/config.json?download=1")!),
            ModelComponent(filename: "model.bin", downloadURL: URL(string: "\(base)/model.bin?download=1")!),
            ModelComponent(filename: "tokenizer.json", downloadURL: URL(string: "\(base)/tokenizer.json?download=1")!),
            ModelComponent(filename: "vocabulary.txt", downloadURL: URL(string: "\(base)/vocabulary.txt?download=1")!)
        ]
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
