import AVFoundation
import Accelerate
import AppKit

final class AudioEngine: NSObject {
    static let shared = AudioEngine()

    private let engine = AVAudioEngine()
    private let converterBus = 0
    private var converter: AVAudioConverter?
    private let processingQueue = DispatchQueue(label: "audio.processing.queue")

    private var buffer16k: [Float] = []
    private var chunkSize: Int = 4096 // 256ms @ 16kHz (for Silero VAD)
    private var running = false
    var isRunning: Bool { running }
    private var isPausedDueToSecureInput = false
    private var sessionStart: Date?

    private let vad = VAD()
    private let asr = ASRClient.shared
    private let notesWindow = NotesWindow.shared

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(onSecureInput(_:)), name: .secureInputChanged, object: nil)
    }

    func startPTT() {
        guard !running else { return }
        guard !SecureInputMonitor.shared.isSecureInputOn else { return }
        running = true
        sessionStart = Date()

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: converterBus)
        let desired = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        converter = AVAudioConverter(from: inputFormat, to: desired)
        // Start ASR stream (Instant mode default)
        let prefs = PreferencesStore.shared.current
        asr.startStream(sampleRate: 16000, modelSize: prefs.modelSize.rawValue, language: "en", offlineOnly: prefs.offlineMode) { ok in
            if !ok { NSLog("[AudioEngine] ASR stream failed to start") }
        }

        input.installTap(onBus: converterBus, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, when) in
            self?.process(buffer: buffer, format: inputFormat, desired: desired)
        }
        do {
            try engine.start()
            NotificationCenter.default.post(name: .hudStateChanged, object: MicHUDView.State.listening)
        } catch {
            NSLog("[AudioEngine] Failed to start: \(error)")
        }
    }

    func stopPTT(dueToSecure: Bool = false) {
        if !dueToSecure {
            isPausedDueToSecureInput = false
        }
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: converterBus)
        engine.stop()
        NotificationCenter.default.post(name: .hudStateChanged, object: MicHUDView.State.thinking)
        let start = sessionStart
        sessionStart = nil
        asr.endStream { text in
            let formattedText = TextFormatter.shared.format(text: text, prefs: PreferencesStore.shared.current)
            let mode = PreferencesStore.shared.current.defaultMode
            if mode == .notes {
                self.notesWindow.makeKeyAndOrderFront(nil)
                self.notesWindow.append(text: formattedText)
                Task { @MainActor in
                    UsageStore.shared.logTranscription(text: formattedText,
                                                       destination: .notes,
                                                       appBundleID: nil,
                                                       startedAt: start,
                                                       endedAt: Date())
                    let wordCount = formattedText.split { $0.isWhitespace || $0.isNewline }.count
                    EventLogStore.shared.record(type: .noteCaptured, message: "Captured note (\(wordCount) words)")
                }
            } else {
                if !formattedText.isEmpty {
                    let outcome = TextInserter.shared.insert(text: formattedText, prefs: PreferencesStore.shared.current)
                    let destination: TranscriptionRecord.Destination
                    var bundleID: String?
                    switch outcome {
                    case .inserted(let bundle):
                        destination = .insertion
                        bundleID = bundle
                    case .clipboard:
                        destination = .clipboard
                        bundleID = nil
                    case .notes:
                        destination = .notes
                        bundleID = nil
                    }
                    Task { @MainActor in
                        UsageStore.shared.logTranscription(text: formattedText,
                                                           destination: destination,
                                                           appBundleID: bundleID,
                                                           startedAt: start,
                                                           endedAt: Date())
                    }
                }
            }
            NotificationCenter.default.post(name: .hudStateChanged, object: MicHUDView.State.idle)
        }
    }

    private func process(buffer: AVAudioPCMBuffer, format: AVAudioFormat, desired: AVAudioFormat) {
        guard let converter else { return }
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        let outBuffer = AVAudioPCMBuffer(pcmFormat: desired, frameCapacity: AVAudioFrameCount(desired.sampleRate / 10))!
        let status = converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        if status == .haveData {
            if let ch = outBuffer.floatChannelData {
                let ptr = ch[0]
                let count = Int(outBuffer.frameLength)
                let arr = Array(UnsafeBufferPointer(start: ptr, count: count))
                appendSamples(arr)
            }
        }
        if let error { NSLog("[AudioEngine] Convert error: \(error)") }
    }

    private func appendSamples(_ samples: [Float]) {
        buffer16k.append(contentsOf: samples)
        // level
        let level = rmsLevel(samples)
        NotificationCenter.default.post(name: .audioLevelDidUpdate, object: CGFloat(level))

        while buffer16k.count >= chunkSize {
            let chunk = Array(buffer16k.prefix(chunkSize))
            buffer16k.removeFirst(chunkSize)
            processingQueue.async {
                let speech = self.vad.isSpeech(chunk: chunk)
                if speech {
                    var data = Data(count: chunk.count * MemoryLayout<Float>.size)
                    data.withUnsafeMutableBytes { raw in
                        let dst = raw.bindMemory(to: Float.self)
                        _ = dst.initialize(from: chunk)
                    }
                    self.asr.sendChunk(data)
                }
            }
        }
    }

    private func rmsLevel(_ samples: [Float]) -> Float {
        var sum: Float = 0
        vDSP_measqv(samples, 1, &sum, vDSP_Length(samples.count))
        let rms = sqrtf(sum)
        let normalized = min(max(rms * 10, 0), 1)
        return normalized
    }

    @objc private func onSecureInput(_ n: Notification) {
        if let on = n.object as? Bool {
            if on {
                if running {
                    isPausedDueToSecureInput = true
                    stopPTT(dueToSecure: true)
                }
            } else {
                if isPausedDueToSecureInput {
                    isPausedDueToSecureInput = false
                    startPTT()
                }
            }
        }
    }
}
