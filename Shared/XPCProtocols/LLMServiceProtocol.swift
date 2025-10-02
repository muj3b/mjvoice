import Foundation

@objc public protocol LLMServiceProtocol {
    func format(text: String, with config: LLMConfig, with reply: @escaping (String) -> Void)
}

@objc public class LLMConfig: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool = true
    public let tone: String
    public let autoCapitalize: Bool
    public let removeFiller: Bool

    public init(tone: String, autoCapitalize: Bool, removeFiller: Bool) {
        self.tone = tone
        self.autoCapitalize = autoCapitalize
        self.removeFiller = removeFiller
    }

    public func encode(with coder: NSCoder) {
        coder.encode(tone, forKey: "tone")
        coder.encode(autoCapitalize, forKey: "autoCapitalize")
        coder.encode(removeFiller, forKey: "removeFiller")
    }

    public required convenience init?(coder: NSCoder) {
        self.init(
            tone: coder.decodeObject(of: NSString.self, forKey: "tone") as String? ?? "neutral",
            autoCapitalize: coder.decodeBool(forKey: "autoCapitalize"),
            removeFiller: coder.decodeBool(forKey: "removeFiller")
        )
    }
}
