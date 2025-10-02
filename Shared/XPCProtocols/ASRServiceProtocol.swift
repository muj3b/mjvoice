import Foundation

@objc public protocol ASRServiceProtocol {
    func startStream(with config: ASRConfig, with reply: @escaping (ASRStartResult) -> Void)
    func sendAudioChunk(_ data: Data, with reply: @escaping (Bool) -> Void)
    func endStream(with reply: @escaping (ASRFinalResult) -> Void)
}

@objc public class ASRConfig: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool = true
    public let sampleRate: Double
    public let modelSize: String
    public let language: String
    public let offlineOnly: Bool
    public let modelIdentifier: String
    public let modelPath: String?
    public let engineHint: String?
    public let noiseModelIdentifier: String
    public let noiseModelPath: String?

    public init(sampleRate: Double,
                modelSize: String,
                language: String,
                offlineOnly: Bool,
                modelIdentifier: String,
                modelPath: String?,
                engineHint: String?,
                noiseModelIdentifier: String,
                noiseModelPath: String?) {
        self.sampleRate = sampleRate
        self.modelSize = modelSize
        self.language = language
        self.offlineOnly = offlineOnly
        self.modelIdentifier = modelIdentifier
        self.modelPath = modelPath
        self.engineHint = engineHint
        self.noiseModelIdentifier = noiseModelIdentifier
        self.noiseModelPath = noiseModelPath
    }

    public func encode(with coder: NSCoder) {
        coder.encode(sampleRate, forKey: "sampleRate")
        coder.encode(modelSize, forKey: "modelSize")
        coder.encode(language, forKey: "language")
        coder.encode(offlineOnly, forKey: "offlineOnly")
        coder.encode(modelIdentifier, forKey: "modelIdentifier")
        coder.encode(modelPath, forKey: "modelPath")
        coder.encode(engineHint, forKey: "engineHint")
        coder.encode(noiseModelIdentifier, forKey: "noiseModelIdentifier")
        coder.encode(noiseModelPath, forKey: "noiseModelPath")
    }

    public required convenience init?(coder: NSCoder) {
        self.init(
            sampleRate: coder.decodeDouble(forKey: "sampleRate"),
            modelSize: coder.decodeObject(of: NSString.self, forKey: "modelSize") as String? ?? "tiny",
            language: coder.decodeObject(of: NSString.self, forKey: "language") as String? ?? "en",
            offlineOnly: coder.decodeBool(forKey: "offlineOnly"),
            modelIdentifier: coder.decodeObject(of: NSString.self, forKey: "modelIdentifier") as String? ?? "whisper-tiny",
            modelPath: coder.decodeObject(of: NSString.self, forKey: "modelPath") as String?,
            engineHint: coder.decodeObject(of: NSString.self, forKey: "engineHint") as String?,
            noiseModelIdentifier: coder.decodeObject(of: NSString.self, forKey: "noiseModelIdentifier") as String? ?? "rnnoise",
            noiseModelPath: coder.decodeObject(of: NSString.self, forKey: "noiseModelPath") as String?
        )
    }
}

@objc public class ASRStartResult: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool = true
    public let ok: Bool
    public let message: String

    public init(ok: Bool, message: String) {
        self.ok = ok
        self.message = message
    }

    public func encode(with coder: NSCoder) {
        coder.encode(ok, forKey: "ok")
        coder.encode(message, forKey: "message")
    }

    public required convenience init?(coder: NSCoder) {
        self.init(ok: coder.decodeBool(forKey: "ok"), message: coder.decodeObject(of: NSString.self, forKey: "message") as String? ?? "")
    }
}

@objc public class ASRFinalResult: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool = true
    public let text: String
    public let segments: [String]

    public init(text: String, segments: [String]) {
        self.text = text
        self.segments = segments
    }

    public func encode(with coder: NSCoder) {
        coder.encode(text, forKey: "text")
        coder.encode(segments, forKey: "segments")
    }

    public required convenience init?(coder: NSCoder) {
        self.init(
            text: coder.decodeObject(of: NSString.self, forKey: "text") as String? ?? "",
            segments: coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "segments") as? [String] ?? []
        )
    }
}
