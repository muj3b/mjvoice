import Foundation

final class ModelLoader {
    static let shared = ModelLoader()

    private(set) var isModelLoaded: Bool = false

    func load(modelSize: String) -> Bool {
        // Look for model at ~/Library/Application Support/mjvoice/Models/whisper-<size>.mlmodelc
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("mjvoice/Models", isDirectory: true)
        let modelURL = dir.appendingPathComponent("whisper-\(modelSize).mlmodelc", isDirectory: true)
        if FileManager.default.fileExists(atPath: modelURL.path) {
            // In real implementation: use Core ML model = try MLModel(contentsOf: modelURL)
            isModelLoaded = true
        } else {
            isModelLoaded = false
        }
        return isModelLoaded
    }
}
