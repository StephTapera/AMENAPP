import XCTest

final class AMENAPPUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    func testLaunchesContextualReactionHarness() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-contextual-reactions")
        app.launch()

        XCTAssertTrue(app.otherElements["contextual_reaction_preview"].waitForExistence(timeout: 5))
    }
}
