import XCTest

final class BereanUITests: XCTestCase {
    func testBereanCorePremiumGateCrisisAndQuotaStates() {
        let app = launchReleaseHarness()

        XCTAssertTrue(app.textFields["Ask Berean"].exists)
        tap("Send Berean Message", in: app)
        XCTAssertTrue(app.staticTexts["Safe Berean response"].waitForExistence(timeout: 2))

        tap("Open Deep Mode", in: app)
        assertEvent("bereanPremiumGateHit", in: app)

        tap("Crisis Fixture", in: app)
        XCTAssertTrue(app.staticTexts["Immediate support: call or text 988"].exists)
        assertEvent("bereanCrisisEscalationDetected", in: app)
    }
}
