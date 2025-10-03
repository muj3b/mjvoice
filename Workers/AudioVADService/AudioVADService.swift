import Foundation
import CoreML

@objc(AudioVADService) final class AudioVADService: NSObject, NSXPCListenerDelegate {
    private let listener = NSXPCListener.service()
    private var idleTimer: DispatchSourceTimer?

    func run() {
        resetIdleTimer()
        listener.delegate = self
        listener.resume()
        loadModel()
        RunLoop.current.run()
    }

    private func resetIdleTimer() {
        idleTimer?.cancel()
        let t = DispatchSource.makeTimerSource()
        t.schedule(deadline: .now() + 5)
        t.setEventHandler { exit(0) }
        t.resume()
        idleTimer = t
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let interface = NSXPCInterface(with: AudioVADServiceProtocol.self)
        newConnection.exportedInterface = interface
        newConnection.exportedObject = self
        newConnection.invalidationHandler = { [weak self] in self?.resetIdleTimer() }
        newConnection.resume()
        return true
    }

    private var vadModel: MLModel?
    private var currentVadState = VadState.initial()
    private let chunkSize = 4096
    private let contextSize = VadState.contextLength
    private let stateSize = VadState.stateLength
    private let modelInputSize = 4096 + VadState.contextLength

    private func loadModel() {
        guard let modelURL = resolveModelURL() else {
            print("[AudioVADService] VAD model not found. XPC VAD will be disabled.")
            return
        }
        do {
            vadModel = try MLModel(contentsOf: modelURL)
            print("[AudioVADService] VAD model loaded: \(modelURL.lastPathComponent)")
        } catch {
            print("[AudioVADService] Failed to load VAD model: \(error)")
        }
    }
    
    private func resolveModelURL() -> URL? {
        // 1) Try bundled resource
        if let url = Bundle.main.url(forResource: "silero-vad-unified-256ms-v6.0.0", withExtension: "mlmodelc", subdirectory: "BundledModels/VAD") {
            return url
        }
        // 2) Try Application Support directory
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let candidate = support.appendingPathComponent("mjvoice/Models/VAD/silero-vad-unified-256ms-v6.0.0.mlmodelc")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }
}

extension AudioVADService: AudioVADServiceProtocol {
    func isSpeechPresent(in chunk: Data, sampleRate: Double, with reply: @escaping (Bool) -> Void) {
        resetIdleTimer()

        guard let model = vadModel else {
            reply(false)
            return
        }

        guard sampleRate == 16000, chunk.count == chunkSize * MemoryLayout<Float>.size else {
            reply(false)
            return
        }

        let samples: [Float] = chunk.withUnsafeBytes { raw in
            Array(UnsafeBufferPointer(start: raw.baseAddress?.assumingMemoryBound(to: Float.self), count: chunkSize))
        }

        do {
            let (probability, newHidden, newCell) = try processUnifiedModel(samples, inputState: currentVadState, model: model)
            currentVadState = VadState(hiddenState: newHidden, cellState: newCell, context: Array(samples.suffix(contextSize)))
            let isSpeech = probability > 0.5
            reply(isSpeech)
        } catch {
            print("VAD process error: \(error)")
            reply(false)
        }
    }
}

@objc protocol AudioVADServiceProtocol {
    func isSpeechPresent(in chunk: Data, sampleRate: Double, with reply: @escaping (Bool) -> Void)
}

private extension AudioVADService {
    func processUnifiedModel(_ audioChunk: [Float], inputState: VadState, model: MLModel) throws -> (Float, [Float], [Float]) {
        let audioArray = try MLMultiArray(shape: [1, NSNumber(value: modelInputSize)], dataType: .float32)
        let hiddenArray = try MLMultiArray(shape: [1, NSNumber(value: stateSize)], dataType: .float32)
        let cellArray = try MLMultiArray(shape: [1, NSNumber(value: stateSize)], dataType: .float32)

        // Populate audio
        for i in 0..<contextSize {
            audioArray[i] = NSNumber(value: inputState.context[i])
        }
        for i in 0..<audioChunk.count {
            audioArray[contextSize + i] = NSNumber(value: audioChunk[i])
        }

        // Populate states
        for i in 0..<stateSize {
            hiddenArray[i] = NSNumber(value: inputState.hiddenState[i])
            cellArray[i] = NSNumber(value: inputState.cellState[i])
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "audio_input": audioArray,
            "hidden_state": hiddenArray,
            "cell_state": cellArray
        ])

        let output = try model.prediction(from: input)

        guard let vadOutput = output.featureValue(for: "vad_output")?.multiArrayValue,
              vadOutput.count == 1 else {
            throw NSError(domain: "VAD", code: 1, userInfo: nil)
        }

        guard let newHidden = output.featureValue(for: "new_hidden_state")?.multiArrayValue,
              newHidden.count == stateSize else {
            throw NSError(domain: "VAD", code: 2, userInfo: nil)
        }

        guard let newCell = output.featureValue(for: "new_cell_state")?.multiArrayValue,
              newCell.count == stateSize else {
            throw NSError(domain: "VAD", code: 3, userInfo: nil)
        }

        let prob = Float(truncating: vadOutput[0])

        var newHiddenArr: [Float] = []
        for i in 0..<stateSize {
            newHiddenArr.append(Float(truncating: newHidden[i]))
        }

        var newCellArr: [Float] = []
        for i in 0..<stateSize {
            newCellArr.append(Float(truncating: newCell[i]))
        }

        return (prob, newHiddenArr, newCellArr)
    }
}

struct VadState {
    static let contextLength = 64
    static let stateLength = 128

    let hiddenState: [Float]
    let cellState: [Float]
    let context: [Float]

    static func initial() -> VadState {
        VadState(
            hiddenState: Array(repeating: 0, count: stateLength),
            cellState: Array(repeating: 0, count: stateLength),
            context: Array(repeating: 0, count: contextLength)
        )
    }
}
