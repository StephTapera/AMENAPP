import XCTest

final class ContextualReactionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPrayerPhraseShowsComposerChip() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-contextual-reactions")
        app.launch()

        let textField = app.textFields["contextual_preview_textfield"]
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
        textField.tap()

        if let existingValue = textField.value as? String, !existingValue.isEmpty {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingValue.count)
            textField.typeText(deleteString)
        }

        textField.typeText("Please pray for me")

        XCTAssertTrue(app.buttons["contextual_reaction_chip_prayerPhrase"].waitForExistence(timeout: 3))
    }

    func testLongPressLikeShowsHiddenReactionRing() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-contextual-reactions")
        app.launch()

        let likeButton = app.buttons["contextual_preview_like_button"]
        XCTAssertTrue(likeButton.waitForExistence(timeout: 5))
        likeButton.press(forDuration: 1.0)

        XCTAssertTrue(app.otherElements["hidden_reaction_ring"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["hidden_reaction_amen"].exists)
        XCTAssertTrue(app.buttons["hidden_reaction_praying"].exists)
    }
}
