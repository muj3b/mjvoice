import Foundation

final class ASRClient {
    static let shared = ASRClient()

    private var connection: NSXPCConnection?
    private var useLocal: Bool = false
    private var localEngine: (any SpeechRecognitionEngine)?

    private var proxy: ASRServiceProtocol? {
        guard !useLocal else { return nil }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] err in
            NSLog("[ASRClient] XPC error: \(err)")
            // Switch to local fallback
            self?.useLocal = true
            NotificationCenter.default.post(name: .asrEngineModeChanged, object: "Local")
            self?.connection?.invalidate()
            self?.connection = nil
        } as? ASRServiceProtocol
    }

    func connect() {
        if connection != nil || useLocal { return }
        let iface = NSXPCInterface(with: ASRServiceProtocol.self)
        let c = NSXPCConnection(serviceName: XPCServiceName.asr.rawValue)
        c.remoteObjectInterface = iface
        c.interruptionHandler = { [weak self] in
            NSLog("[ASRClient] XPC interruption")
            self?.useLocal = true
            NotificationCenter.default.post(name: .asrEngineModeChanged, object: "Local")
            self?.connection?.invalidate()
            self?.connection = nil
        }
        c.invalidationHandler = { [weak self] in
            NSLog("[ASRClient] XPC invalidation")
            self?.useLocal = true
            NotificationCenter.default.post(name: .asrEngineModeChanged, object: "Local")
            self?.connection?.invalidate()
            self?.connection = nil
        }
        c.resume()
        NotificationCenter.default.post(name: .asrEngineModeChanged, object: "XPC")
        connection = c
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

        if let proxy = proxy {
            proxy.startStream(with: cfg) { res in
                if !res.ok {
                    // Fallback if service failed to start
                    self.startLocal(with: cfg, completion: completion)
                } else {
                    completion(true)
                }
            }
        } else {
            // No XPC available; use local engine
            startLocal(with: cfg, completion: completion)
        }
    }

    private func startLocal(with cfg: ASRConfig, completion: @escaping (Bool) -> Void) {
        do {
            let engine = try selectEngine(for: cfg)
            self.localEngine = engine
            self.useLocal = true
            NotificationCenter.default.post(name: .asrEngineModeChanged, object: "Local")
            Task {
                do {
                    try await engine.start(config: cfg)
                    completion(true)
                } catch {
                    NSLog("[ASRClient] Local engine start failed: \(error)")
                    completion(false)
                }
            }
        } catch {
            NSLog("[ASRClient] Failed to select local engine: \(error)")
            completion(false)
        }
    }

    func sendChunk(_ data: Data) {
        if useLocal, let localEngine {
            localEngine.appendAudio(data: data)
        } else {
            proxy?.sendAudioChunk(data) { _ in }
        }
    }

    func endStream(completion: @escaping (String) -> Void) {
        if useLocal, let engine = localEngine {
            Task { [weak self] in
                let (text, _) = await engine.finish()
                completion(text)
                self?.localEngine = nil
                self?.useLocal = false
            }
        } else {
            proxy?.endStream { result in
                completion(result.text)
            }
        }
    }

    private func selectEngine(for config: ASRConfig) throws -> any SpeechRecognitionEngine {
        return NoopEngine()
    }
}

private final class NoopEngine: SpeechRecognitionEngine {
    func start(config: ASRConfig) async throws {
        NSLog("[NoopEngine] Local engine not available in this build; using no-op.")
    }

    func appendAudio(data: Data) {
        // no-op
    }

    func finish() async -> (String, [String]) {
        return ("", [])
    }
}
