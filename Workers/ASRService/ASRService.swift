import Foundation
import AppKit

@objc(ASRService) final class ASRService: NSObject, NSXPCListenerDelegate {
    private let listener: NSXPCListener
    private var idleTimer: DispatchSourceTimer?
    private var engine: WhisperEngine?

    override init() {
        listener = NSXPCListener.service()
        super.init()
        listener.delegate = self
    }

    func run() {
        resetIdleTimer()
        listener.resume()
        RunLoop.current.run()
    }

    private func resetIdleTimer() {
        idleTimer?.cancel()
        let t = DispatchSource.makeTimerSource()
        t.schedule(deadline: .now() + 5)
        t.setEventHandler { [weak self] in
            self?.engine = nil
            exit(0)
        }
        t.resume()
        idleTimer = t
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let interface = NSXPCInterface(with: ASRServiceProtocol.self)
        newConnection.exportedInterface = interface
        newConnection.exportedObject = self
        newConnection.invalidationHandler = { [weak self] in self?.resetIdleTimer() }
        newConnection.resume()
        return true
    }
}

extension ASRService: ASRServiceProtocol {
    func startStream(with config: ASRConfig, with reply: @escaping (ASRStartResult) -> Void) {
        if engine == nil { engine = WhisperEngine() }
        resetIdleTimer()
        engine?.start(config: config)
        reply(ASRStartResult(ok: true, message: "started"))
    }

    func sendAudioChunk(_ data: Data, with reply: @escaping (Bool) -> Void) {
        resetIdleTimer()
        engine?.appendAudio(data: data)
        reply(true)
    }

    func endStream(with reply: @escaping (ASRFinalResult) -> Void) {
        resetIdleTimer()
        Task {
            let (text, segments) = await self.engine?.finish() ?? ("", [])
            reply(ASRFinalResult(text: text, segments: segments))
        }
    }
}

@objc protocol ASRServiceProtocol {
    func startStream(with config: ASRConfig, with reply: @escaping (ASRStartResult) -> Void)
    func sendAudioChunk(_ data: Data, with reply: @escaping (Bool) -> Void)
    func endStream(with reply: @escaping (ASRFinalResult) -> Void)
}

@objc class ASRConfig: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool = true
    let sampleRate: Double
    let modelSize: String
    let language: String
    let offlineOnly: Bool

    init(sampleRate: Double, modelSize: String, language: String, offlineOnly: Bool) {
        self.sampleRate = sampleRate
        self.modelSize = modelSize
        self.language = language
        self.offlineOnly = offlineOnly
    }

    func encode(with coder: NSCoder) {
        coder.encode(sampleRate, forKey: "sampleRate")
        coder.encode(modelSize, forKey: "modelSize")
        coder.encode(language, forKey: "language")
        coder.encode(offlineOnly, forKey: "offlineOnly")
    }

    required convenience init?(coder: NSCoder) {
        self.init(sampleRate: coder.decodeDouble(forKey: "sampleRate"),
                  modelSize: coder.decodeObject(of: NSString.self, forKey: "modelSize") as String? ?? "tiny",
                  language: coder.decodeObject(of: NSString.self, forKey: "language") as String? ?? "en",
                  offlineOnly: coder.decodeBool(forKey: "offlineOnly"))
    }
}

@objc class ASRStartResult: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool = true
    let ok: Bool
    let message: String
    init(ok: Bool, message: String) { self.ok = ok; self.message = message }
    func encode(with coder: NSCoder) { coder.encode(ok, forKey: "ok"); coder.encode(message, forKey: "message") }
    required convenience init?(coder: NSCoder) { self.init(ok: coder.decodeBool(forKey: "ok"), message: coder.decodeObject(of: NSString.self, forKey: "message") as String? ?? "") }
}

@objc class ASRFinalResult: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool = true
    let text: String
    let segments: [String]
    init(text: String, segments: [String]) { self.text = text; self.segments = segments }
    func encode(with coder: NSCoder) { coder.encode(text, forKey: "text"); coder.encode(segments, forKey: "segments") }
    required convenience init?(coder: NSCoder) { self.init(text: coder.decodeObject(of: NSString.self, forKey: "text") as String? ?? "", segments: coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "segments") as? [String] ?? []) }
}
