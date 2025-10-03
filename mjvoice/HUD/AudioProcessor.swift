import AVFoundation
import Accelerate

final class AudioProcessor: NSObject {
    private let audioEngine = AVAudioEngine()
    private var smoothedLevel: Float = 0
    private let attackCoefficient: Float = 0.18
    private let releaseCoefficient: Float = 0.035
    private var isRunning = false

    var onAudioLevelUpdate: ((Float) -> Void)?

    override init() {
        super.init()
        configureEngine()
    }

    deinit {
        stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func configureEngine() {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 256, format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }
    }

    func start() {
        guard !isRunning else { return }

        let requestAccess: (Bool) -> Void = { [weak self] granted in
            guard granted, let self else {
                NSLog("[AudioProcessor] Microphone access denied")
                return
            }
            do {
                try self.audioEngine.start()
                self.isRunning = true
            } catch {
                NSLog("[AudioProcessor] Failed to start audio engine: \(error)")
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            requestAccess(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: requestAccess)
        default:
            requestAccess(false)
        }
    }

    func stop() {
        guard isRunning else { return }
        audioEngine.stop()
        isRunning = false
        smoothedLevel = 0
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevelUpdate?(0)
        }
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))

        let db = 20 * log10f(max(rms, 0.00001))
        let normalized = max(0, min(1, (db + 45) / 35))

        let coefficient: Float = normalized > smoothedLevel ? attackCoefficient : releaseCoefficient
        smoothedLevel += (normalized - smoothedLevel) * coefficient

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onAudioLevelUpdate?(self.smoothedLevel)
        }
    }
}
