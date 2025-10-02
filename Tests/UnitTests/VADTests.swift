import XCTest
@testable import mjvoice

final class VADTests: XCTestCase {
    func testSilenceIsNotSpeech() {
        let vad = VAD()
        let chunk = Array(repeating: Float(0.0), count: 1600)
        XCTAssertFalse(vad.isSpeech(chunk: chunk))
    }

    func testNoiseLikelySpeech() {
        let vad = VAD()
        var chunk: [Float] = []
        for i in 0..<1600 { chunk.append(sinf(Float(i) * 0.05)) }
        XCTAssertTrue(vad.isSpeech(chunk: chunk))
    }
}
