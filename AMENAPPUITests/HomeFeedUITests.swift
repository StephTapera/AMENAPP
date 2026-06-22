import XCTest

final class HomeFeedUITests: XCTestCase {
    func testHomeFeedDailyVerseHeyFeedComposerAndPostActions() {
        let app = launchReleaseHarness()

        XCTAssertTrue(app.staticTexts["Eligible seeded post"].exists)
        XCTAssertTrue(app.staticTexts["Removed flagged deleted posts hidden"].exists)
        XCTAssertFalse(app.staticTexts["Removed seeded post"].exists)
        XCTAssertFalse(app.staticTexts["Flagged seeded post"].exists)

        tap("Daily Verse John 3:16 KJV", in: app)
        tap("Open Hey Feed", in: app)

        let composer = app.textFields["post_composer"]
        XCTAssertTrue(composer.exists)
        composer.tap()
        composer.typeText("Home test")
        tap("Create Post", in: app)

        for label in ["Amen reaction", "Lightbulb", "Comment", "Repost", "Share", "More"] {
            let control = app.buttons[label]
            XCTAssertTrue(control.exists)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
            control.tap()
        }
    }
}
