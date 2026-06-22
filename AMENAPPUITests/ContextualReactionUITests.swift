import XCTest

final class ContextualReactionUITests: XCTestCase {
    func testComposerShowsPrayerChip() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-contextual-reactions")
        app.launch()

        let textField = app.textFields["contextual_preview_textfield"]
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
        textField.tap()

        if let currentValue = textField.value as? String, !currentValue.isEmpty {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
            textField.typeText(deleteString)
        }

        textField.typeText("Please pray for me")
        XCTAssertTrue(app.buttons["contextual_reaction_chip_prayerPhrase"].waitForExistence(timeout: 2))
    }

    func testLongPressShowsHiddenReactionRing() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-contextual-reactions")
        app.launch()

        let likeButton = app.buttons["contextual_preview_like_button"]
        XCTAssertTrue(likeButton.waitForExistence(timeout: 5))
        likeButton.press(forDuration: 0.6)

        XCTAssertTrue(app.otherElements["hidden_reaction_ring"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["hidden_reaction_amen"].exists)
        XCTAssertTrue(app.buttons["hidden_reaction_praying"].exists)
    }
}
