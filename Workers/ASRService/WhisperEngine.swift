import Foundation
import WhisperKit

final class WhisperEngine: SpeechRecognitionEngine {
    private var started = false
    private var audioData = Data()
    private var whisperKit: WhisperKit?

    func start(config: ASRConfig) async throws {
        started = true
        audioData.removeAll(keepingCapacity: true)

        if let modelPath = config.modelPath {
            let folderURL = URL(fileURLWithPath: modelPath).deletingLastPathComponent()
            let fileName = URL(fileURLWithPath: modelPath).lastPathComponent
            let configuration = WhisperKitConfig(model: fileName,
                                                 modelFolder: folderURL,
                                                 download: false,
                                                 load: true)
            whisperKit = try await WhisperKit(configuration)
        } else {
            let identifier = config.modelIdentifier
            let mapped = identifier.split(separator: "-").last.map(String.init) ?? config.modelSize
            whisperKit = try await WhisperKit(model: mapped)
        }
    }

    func appendAudio(data: Data) {
        guard started else { return }
        audioData.append(data)
    }

    func finish() async -> (String, [String]) {
        defer {
            started = false
            audioData.removeAll(keepingCapacity: false)
        }

        guard let whisperKit else {
            return ("", [])
        }

        let floatArray = audioData.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Float.self))
        }

        do {
            let transcription = try await whisperKit.transcribe(audioArray: floatArray)
            return (transcription.text, transcription.segments.map { $0.text })
        } catch {
            NSLog("[WhisperEngine] Transcription failed: \(error)")
            return ("", [])
        }
    }
}
