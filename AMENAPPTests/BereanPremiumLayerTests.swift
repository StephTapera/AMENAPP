import XCTest
@testable import AMENAPP

final class BereanPremiumModeTests: XCTestCase {
    func testMainBereanModesExposeProductSurfaceOnly() {
        XCTAssertEqual(BereanPersonalityMode.allCases, [
            .shepherd,
            .scholar,
            .coach,
            .builder,
            .strategist,
            .creator,
            .debater
        ])
    }

    func testLegacyModesRemainDecodableForSavedConversations() {
        XCTAssertEqual(BereanPersonalityMode(rawValue: "Shepherd"), .shepherd)
        XCTAssertEqual(BereanPersonalityMode(rawValue: "Scholar"), .scholar)
    }

    func testShepherdModePromptKeepsPastoralGuardrails() {
        let prompt = BereanPersonalityMode.shepherd.systemPromptPrefix
        XCTAssertTrue(prompt.contains("warm, pastoral"))
        XCTAssertTrue(prompt.contains("Scripture"))
    }
}

@MainActor
final class BereanStructuredBlockRenderingTests: XCTestCase {
    func testEveryRequestedAssistantBlockTypeDecodes() throws {
        let rawTypes = [
            "text",
            "verse_card",
            "cross_reference_card",
            "historical_context_card",
            "greek_hebrew_word_card",
            "prayer_card",
            "discernment_framework_card",
            "summary_card",
            "caution_card",
            "action_step_card",
            "saved_insight_card",
            "media_key_moment_card",
            "safety_notice_card"
        ]

        for rawType in rawTypes {
            let json = """
            {
              "id": "\(rawType)",
              "type": "\(rawType)",
              "title": "Title",
              "content": "Content",
              "scriptureRef": null,
              "resourceURL": null,
              "sortOrder": 0
            }
            """.data(using: .utf8)!
            XCTAssertNoThrow(try JSONDecoder().decode(StudyCard.self, from: json), rawType)
        }
    }

    func testPrayerCardDefaultsToPrivateSemanticType() {
        let card = StudyCard(
            id: "prayer",
            type: .prayerCard,
            title: "Prayer",
            content: "Lord, help me walk in wisdom.",
            scriptureRef: "James 1:5",
            resourceURL: nil,
            sortOrder: 0
        )

        XCTAssertEqual(card.type, .prayerCard)
        XCTAssertEqual(card.scriptureRef, "James 1:5")
    }
}
