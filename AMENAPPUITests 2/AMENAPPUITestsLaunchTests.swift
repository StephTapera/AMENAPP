import XCTest

final class AMENAPPUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchesContextualReactionHarness() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-contextual-reactions")
        app.launch()

        XCTAssertTrue(app.otherElements["contextual_reaction_preview"].waitForExistence(timeout: 5))
    }
}
