import XCTest

final class Phase34DiscoveryComposerUIFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDiscoveryPhotosAndVideosTopicChipsAndNoViewCount() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-phase34", "--ui-test-disable-composer-audio"]
        app.launch()

        if app.tabBars.firstMatch.exists {
            for candidate in ["Discover", "Discovery", "Search"] {
                let button = app.tabBars.buttons[candidate]
                if button.exists {
                    button.tap()
                    break
                }
            }
        }

        let mediaView = app.otherElements["discovery_photos_videos_view"]
        XCTAssertTrue(mediaView.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Photos & Videos"].exists)

        XCTAssertTrue(app.buttons["discovery_topic_chip_for_you"].exists)
        XCTAssertTrue(app.buttons["discovery_topic_chip_worship"].exists)
        XCTAssertTrue(app.buttons["discovery_topic_chip_prayer"].exists)
        XCTAssertTrue(app.buttons["discovery_topic_chip_testimony"].exists)
        XCTAssertTrue(app.buttons["discovery_topic_chip_scripture"].exists)
        XCTAssertTrue(app.buttons["discovery_topic_chip_churches"].exists)

        let viewsPredicate = NSPredicate(format: "label CONTAINS[c] 'views'")
        XCTAssertEqual(mediaView.staticTexts.containing(viewsPredicate).count, 0)
    }

    func testComposerAddMusicHiddenWhenFlagOff() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-disable-composer-audio"]
        app.launch()

        try openComposerIfPossible(app)
        XCTAssertFalse(app.buttons["composer_add_music_button"].exists)
    }

    func testComposerAddMusicVisibleWithFlagOnAndMockMediaAndPickerIsGuarded() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-enable-composer-audio", "--ui-test-attach-mock-media"]
        app.launch()

        try openComposerIfPossible(app)

        let addMusicButton = app.buttons["composer_add_music_button"]
        XCTAssertTrue(addMusicButton.waitForExistence(timeout: 6))

        addMusicButton.tap()
        XCTAssertTrue(app.otherElements["amen_audio_composer_sheet"].waitForExistence(timeout: 5))

        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Spotify'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Apple Music'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Approved Amen audio only. Public reuse requires approved tracks."].exists)
    }

    private func openComposerIfPossible(_ app: XCUIApplication) throws {
        if app.otherElements["create_post_view"].waitForExistence(timeout: 3) { return }

        let candidates: [XCUIElement] = [
            app.buttons["Create"],
            app.buttons["Post"],
            app.buttons["Compose"],
            app.buttons["New Post"],
            app.navigationBars.buttons["Create"],
            app.navigationBars.buttons["Post"]
        ]

        for element in candidates where element.exists {
            element.tap()
            if app.otherElements["create_post_view"].waitForExistence(timeout: 4) { return }
        }

        throw XCTSkip("Composer entrypoint not discoverable in current runtime configuration")
    }
}
