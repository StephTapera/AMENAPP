import XCTest

final class Phase34DiscoveryComposerUITests: XCTestCase {
    func testDiscoveryComposerReleaseHarnessDoesNotSkip() {
        let app = launchReleaseHarness()
        XCTAssertTrue(app.staticTexts["Eligible seeded post"].exists)
        let composer = app.textFields["post_composer"]
        XCTAssertTrue(composer.exists)
        composer.tap()
        composer.typeText("Discovery composer release test")
        tap("Create Post", in: app)
        XCTAssertTrue(app.staticTexts["Post action row visible"].waitForExistence(timeout: 2))
    }
}
