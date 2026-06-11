import XCTest
@testable import AMENAPP

final class XCTestSmokeDiscoveryTests: XCTestCase {
    func testDiscoverySmoke() {
        XCTAssertTrue(true)
        XCTAssertNotNil(AMENFeatureFlags.shared, "AMENFeatureFlags singleton must be accessible")
    }
}
