import Foundation
import WhisperKit

// Actual WhisperKit implementation
final class WhisperEngine {
    private var started = false
    private var audioData = Data()
    private var config: ASRConfig?
    private var whisperKit: WhisperKit?

    func start(config: ASRConfig) {
        self.config = config
        started = true
        audioData.removeAll(keepingCapacity: true)

        // Initialize WhisperKit with model
        Task {
            do {
                let model = config.modelSize
                self.whisperKit = try await WhisperKit(model: model)
            } catch {
                NSLog("[WhisperEngine] Failed to load model: \(error)")
            }
        }
    }

    func appendAudio(data: Data) {
        guard started else { return }
        audioData.append(data)
    }

    func finish() async -> (String, [String]) {
        defer { started = false; audioData.removeAll() }

        guard let whisperKit else {
            return ("", [])
        }

        // Convert audio data to float array
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
