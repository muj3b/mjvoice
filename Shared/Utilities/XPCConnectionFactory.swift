import Foundation

public enum XPCServiceName: String {
    case asr = "com.mjvoice.ASRService"
    case llm = "com.mjvoice.LLMService"
    case vad = "com.mjvoice.AudioVADService"
}

public final class XPCConnectionFactory {
    public static func makeConnection(_ service: XPCServiceName, remoteInterface: NSXPCInterface, exportedInterface: NSXPCInterface? = nil, exportedObject: Any? = nil) -> NSXPCConnection {
        let c = NSXPCConnection(serviceName: service.rawValue)
        c.remoteObjectInterface = remoteInterface
        if let exportedInterface, let exportedObject {
            c.exportedInterface = exportedInterface
            c.exportedObject = exportedObject as AnyObject
        }
        c.interruptionHandler = { NSLog("[XPC] Interruption: \(service.rawValue)") }
        c.invalidationHandler = { NSLog("[XPC] Invalidation: \(service.rawValue)") }
        c.resume()
        return c
    }
}
