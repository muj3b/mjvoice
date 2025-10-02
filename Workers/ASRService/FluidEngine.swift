import Foundation
import AVFoundation

final class FluidEngine: SpeechRecognitionEngine {
    private var audioSamples: [Float] = []
    private var runtime: FluidRuntime?
    private var sampleRate: Double = 16000

    func start(config: ASRConfig) async throws {
        guard let modelPath = config.modelPath, FileManager.default.fileExists(atPath: modelPath) else {
            throw SpeechRecognitionEngineError.modelNotAvailable
        }
        runtime = try FluidRuntime(modelPath: modelPath, engineHint: config.engineHint)
        audioSamples.removeAll(keepingCapacity: true)
        sampleRate = config.sampleRate
    }

    func appendAudio(data: Data) {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            let floats = base.assumingMemoryBound(to: Float.self)
            let count = buffer.count / MemoryLayout<Float>.size
            audioSamples.append(contentsOf: UnsafeBufferPointer(start: floats, count: count))
        }
    }

    func finish() async -> (String, [String]) {
        guard let runtime else { return ("", []) }
        do {
            let wavURL = try writeTemporaryWav(samples: audioSamples, sampleRate: sampleRate)
            defer { try? FileManager.default.removeItem(at: wavURL) }
            let result = try runtime.transcribe(audioURL: wavURL)
            return (result.text, result.segments)
        } catch {
            NSLog("[FluidEngine] Transcription failed: \(error)")
            return ("", [])
        }
    }

    private func writeTemporaryWav(samples: [Float], sampleRate: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fluid-\(UUID().uuidString).wav")
        var pcm = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            let clipped = max(-1.0, min(1.0, Double(sample)))
            let intSample = Int16(clipped * Double(Int16.max))
            var little = intSample.littleEndian
            pcm.append(UnsafeBufferPointer(start: &little, count: 1))
        }

        let dataSize = UInt32(pcm.count)
        let fmtChunkSize: UInt32 = 16
        let audioFormat: UInt16 = 1 // PCM
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = UInt16(numChannels * bitsPerSample / 8)
        let chunkSize = UInt32(36) + dataSize

        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.append(chunkSize.littleEndianData)
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(fmtChunkSize.littleEndianData)
        header.append(audioFormat.littleEndianData)
        header.append(numChannels.littleEndianData)
        header.append(UInt32(sampleRate).littleEndianData)
        header.append(byteRate.littleEndianData)
        header.append(blockAlign.littleEndianData)
        header.append(bitsPerSample.littleEndianData)
        header.append("data".data(using: .ascii)!)
        header.append(dataSize.littleEndianData)
        header.append(pcm)

        try header.write(to: url)
        return url
    }
}

private struct FluidTranscriptionResult: Decodable {
    let text: String
    let segments: [String]
}

private struct FluidRuntime {
    enum RuntimeType {
        case executable(URL)
    }

    private let runtime: RuntimeType
    private let modelPath: String

    init(modelPath: String, engineHint: String?) throws {
        self.modelPath = modelPath
        if let runtimeFromEnv = ProcessInfo.processInfo.environment["MJVOICE_FLUID_RUNTIME"], !runtimeFromEnv.isEmpty {
            runtime = .executable(URL(fileURLWithPath: runtimeFromEnv))
            return
        }

        let modelDirectory = URL(fileURLWithPath: modelPath).deletingLastPathComponent()
        let bundled = modelDirectory.appendingPathComponent("fluid-runner")
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            runtime = .executable(bundled)
            return
        }

        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let defaultRunner = supportDir.appendingPathComponent("mjvoice/bin/fluid-runner")
        if FileManager.default.isExecutableFile(atPath: defaultRunner.path) {
            runtime = .executable(defaultRunner)
            return
        }

        throw SpeechRecognitionEngineError.runtimeNotAvailable("Install the Fluid runtime (set MJVOICE_FLUID_RUNTIME or place a fluid-runner executable alongside the model).")
    }

    func transcribe(audioURL: URL) throws -> (text: String, segments: [String]) {
        switch runtime {
        case .executable(let url):
            return try runExecutable(url, audioURL: audioURL)
        }
    }

    private func runExecutable(_ executableURL: URL, audioURL: URL) throws -> (text: String, segments: [String]) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--model", modelPath, "--audio", audioURL.path, "--format", "json"]
        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorString = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown error"
            throw SpeechRecognitionEngineError.initializationFailed("Fluid runtime failed: \(errorString)")
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        if let decoded = try? JSONDecoder().decode(FluidTranscriptionResult.self, from: data) {
            return (decoded.text, decoded.segments)
        }
        let fallback = String(data: data, encoding: .utf8) ?? ""
        return (fallback.trimmingCharacters(in: .whitespacesAndNewlines), [])
    }
}

private extension UInt16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}

private extension UInt32 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}
