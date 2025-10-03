import Foundation

enum DictationOverlayState: String, Codable {
    case idle
    case listening
    case thinking
    case inserting
    case error
}
