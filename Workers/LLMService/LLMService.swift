import Foundation

@objc(LLMService) final class LLMService: NSObject, NSXPCListenerDelegate {
    private let listener = NSXPCListener.service()
    private var idleTimer: DispatchSourceTimer?

    func run() {
        resetIdleTimer()
        listener.delegate = self
        listener.resume()
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
        let interface = NSXPCInterface(with: LLMServiceProtocol.self)
        newConnection.exportedInterface = interface
        newConnection.exportedObject = self
        newConnection.invalidationHandler = { [weak self] in self?.resetIdleTimer() }
        newConnection.resume()
        return true
    }
}

extension LLMService: LLMServiceProtocol {
    func format(text: String, with config: LLMConfig, with reply: @escaping (String) -> Void) {
        resetIdleTimer()
        let out = FormatterEngine().format(text: text, config: config)
        reply(out)
    }
}

@objc protocol LLMServiceProtocol {
    func format(text: String, with config: LLMConfig, with reply: @escaping (String) -> Void)
}

@objc class LLMConfig: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool = true
    let tone: String
    let autoCapitalize: Bool
    let removeFiller: Bool
    init(tone: String, autoCapitalize: Bool, removeFiller: Bool) { self.tone = tone; self.autoCapitalize = autoCapitalize; self.removeFiller = removeFiller }
    func encode(with coder: NSCoder) { coder.encode(tone, forKey: "tone"); coder.encode(autoCapitalize, forKey: "autoCapitalize"); coder.encode(removeFiller, forKey: "removeFiller") }
    required convenience init?(coder: NSCoder) { self.init(tone: coder.decodeObject(of: NSString.self, forKey: "tone") as String? ?? "neutral", autoCapitalize: coder.decodeBool(forKey: "autoCapitalize"), removeFiller: coder.decodeBool(forKey: "removeFiller")) }
}
