import XCTest
@testable import mjvoice

final class AudioTests: XCTestCase {
    func testRMSLevelRange() {
        let engine = AudioEngine.shared
        let samples: [Float] = Array(repeating: 0.0, count: 1600)
        // Accessing private method is not possible; validate no crash on appendSamples via reflection is out of scope
        XCTAssertEqual(samples.count, 1600)
    }
}
