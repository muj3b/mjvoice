import Foundation

protocol SpeechRecognitionEngine: AnyObject {
    func start(config: ASRConfig) async throws
    func appendAudio(data: Data)
    func finish() async -> (String, [String])
}

enum SpeechRecognitionEngineError: LocalizedError {
    case modelNotAvailable
    case runtimeNotAvailable(String)
    case initializationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable:
            return "The selected speech model could not be found on disk."
        case .runtimeNotAvailable(let message):
            return message
        case .initializationFailed(let message):
            return message
        }
    }
}
