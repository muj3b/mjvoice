import Foundation

final class ASRClient {
    static let shared = ASRClient()

    private var connection: NSXPCConnection?
    private var proxy: ASRServiceProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { err in
            NSLog("[ASRClient] XPC error: \(err)")
        } as? ASRServiceProtocol
    }

    func connect() {
        if connection != nil { return }
        let iface = NSXPCInterface(with: ASRServiceProtocol.self)
        connection = NSXPCConnection(serviceName: XPCServiceName.asr.rawValue)
        connection?.remoteObjectInterface = iface
        connection?.resume()
    }

    func startStream(sampleRate: Double, modelSize: String, language: String, offlineOnly: Bool, completion: @escaping (Bool) -> Void) {
        connect()
        let prefs = PreferencesStore.shared.current
        let asrResolution = ModelManager.shared.resolveASRModel(preferences: prefs)
        let noiseResolution = ModelManager.shared.resolveNoiseModel(preferences: prefs)
        let cfg = ASRConfig(sampleRate: sampleRate,
                            modelSize: modelSize,
                            language: language,
                            offlineOnly: offlineOnly,
                            modelIdentifier: asrResolution.identifier,
                            modelPath: asrResolution.url?.path,
                            engineHint: asrResolution.descriptor?.engineHint,
                            noiseModelIdentifier: noiseResolution.identifier,
                            noiseModelPath: noiseResolution.url?.path)
        proxy?.startStream(with: cfg) { res in
            completion(res.ok)
        }
    }

    func sendChunk(_ data: Data) {
        proxy?.sendAudioChunk(data) { _ in }
    }

    func endStream(completion: @escaping (String) -> Void) {
        proxy?.endStream { result in
            completion(result.text)
        }
    }
}
