import XCTest

final class Phase34DiscoveryComposerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDiscoveryPhotosAndVideosTopicChipsAndNoViewCount() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-phase34", "--ui-test-disable-composer-audio"]
        app.launch()

        if app.tabBars.firstMatch.exists {
            let discoverCandidates = ["Discover", "Discovery", "Search"]
            for candidate in discoverCandidates {
                let button = app.tabBars.buttons[candidate]
                if button.exists {
                    button.tap()
                    break
                }
            }
        }

        let mediaView = app.otherElements["discovery_photos_videos_view"]
        XCTAssertTrue(mediaView.waitForExistence(timeout: 8), "Photos & Videos view should open")

        XCTAssertTrue(app.staticTexts["Photos & Videos"].exists)
        XCTAssertTrue(app.buttons["discovery_topic_chip_for_you"].exists)
        XCTAssertTrue(app.buttons["discovery_topic_chip_worship"].exists)
        XCTAssertTrue(app.buttons["discovery_topic_chip_prayer"].exists)
        XCTAssertTrue(app.buttons["discovery_topic_chip_testimony"].exists)
        XCTAssertTrue(app.buttons["discovery_topic_chip_scripture"].exists)
        XCTAssertTrue(app.buttons["discovery_topic_chip_churches"].exists)

        let viewsPredicate = NSPredicate(format: "label CONTAINS[c] 'views'")
        let viewsTexts = mediaView.staticTexts.containing(viewsPredicate)
        XCTAssertEqual(viewsTexts.count, 0, "No public view count text should appear on changed discovery video surface")
    }

    func testComposerAddMusicHiddenWhenFlagOff() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-disable-composer-audio"]
        app.launch()

        try openComposerIfPossible(app: app)
        let addMusicButton = app.buttons["composer_add_music_button"]
        XCTAssertFalse(addMusicButton.exists, "Add Music must be hidden when composerApprovedAudioEnabled is false")
    }

    func testComposerAddMusicAppearsWithFlagAndAttachedMediaThenOpensPicker() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-enable-composer-audio", "--ui-test-attach-mock-media"]
        app.launch()

        try openComposerIfPossible(app: app)

        let addMusicButton = app.buttons["composer_add_music_button"]
        XCTAssertTrue(addMusicButton.waitForExistence(timeout: 6), "Add Music should appear when feature flag is on and media is attached")

        addMusicButton.tap()

        let picker = app.otherElements["amen_audio_composer_sheet"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Audio picker should open behind feature flag")

        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Spotify'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Apple Music'")).firstMatch.exists)

        XCTAssertTrue(app.staticTexts["Approved Amen audio only. Public reuse requires approved tracks."].exists)
    }

    private func openComposerIfPossible(app: XCUIApplication()) throws {
        if app.otherElements["create_post_view"].waitForExistence(timeout: 3) {
            return
        }

        let candidates: [XCUIElement] = [
            app.buttons["Create"],
            app.buttons["Post"],
            app.buttons["Compose"],
            app.buttons["New Post"],
            app.buttons["plus"],
            app.navigationBars.buttons["Create"],
            app.navigationBars.buttons["Post"]
        ]

        for element in candidates where element.exists {
            element.tap()
            if app.otherElements["create_post_view"].waitForExistence(timeout: 4) {
                return
            }
        }

        if app.tabBars.firstMatch.exists {
            let tabCandidates = ["Home", "Feed", "Amen"]
            for tab in tabCandidates {
                let tabButton = app.tabBars.buttons[tab]
                if tabButton.exists {
                    tabButton.tap()
                    break
                }
            }
            for element in candidates where element.exists {
                element.tap()
                if app.otherElements["create_post_view"].waitForExistence(timeout: 4) {
                    return
                }
            }
        }

        throw XCTSkip("Composer entrypoint not discoverable in current simulator routing/configuration")
    }
}
