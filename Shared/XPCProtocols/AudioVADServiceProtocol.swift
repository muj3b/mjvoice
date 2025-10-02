import Foundation

@objc public protocol AudioVADServiceProtocol {
    func isSpeechPresent(in chunk: Data, sampleRate: Double, with reply: @escaping (Bool) -> Void)
}
