import XCTest
@testable import mjvoice

final class TextInsertionTests: XCTestCase {
    func testSecureInputGuard() {
        // Cannot toggle Secure Input in tests; ensure shared property exists and default is false
        XCTAssertFalse(SecureInputMonitor.shared.isSecureInputOn)
    }
}
