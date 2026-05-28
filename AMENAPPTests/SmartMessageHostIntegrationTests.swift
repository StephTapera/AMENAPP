import Testing
@testable import AMENAPP

@MainActor
struct SmartMessageHostIntegrationTests {
    @Test func scriptureDetectionCreatesScriptureActions() async throws {
        let entities = SmartMessageLocalDetector.detect(in: "Read Romans 8:28 tonight", respectFeatureFlags: false)
        #expect(entities.contains { $0.type == .scriptureReference })
        let scripture = try #require(entities.first { $0.type == .scriptureReference })
        let actions = SmartMessageLocalDetector.actions(for: scripture, context: .local(messageId: "m1", surface: "test"))
        #expect(actions.contains { $0.actionType == .openScripture })
        #expect(actions.contains { $0.actionType == .askBerean })
        #expect(actions.contains { $0.actionType == .startStudyMode })
    }

    @Test func dateDetectionCreatesCalendarAndReminderActions() async throws {
        let entities = SmartMessageLocalDetector.detect(in: "Bible study Friday at 7pm", respectFeatureFlags: false)
        let date = try #require(entities.first { $0.type == .dateTime })
        let actions = SmartMessageLocalDetector.actions(for: date, context: .local(messageId: "m2", surface: "test"))
        #expect(actions.contains { $0.actionType == .addToCalendar })
        #expect(actions.contains { $0.actionType == .addReminder })
    }

    @Test func prayerDetectionRequiresConfirmationAction() async throws {
        let entities = SmartMessageLocalDetector.detect(in: "Please pray for my family", respectFeatureFlags: false)
        let prayer = try #require(entities.first { $0.type == .prayerRequest })
        let actions = SmartMessageLocalDetector.actions(for: prayer, context: .local(messageId: "m3", surface: "test"))
        let create = try #require(actions.first { $0.actionType == .createPrayerRequest })
        #expect(create.requiresConfirmation)
    }

    @Test func topicDetectionCreatesSearchStudyGraphActions() async throws {
        let entities = SmartMessageLocalDetector.detect(in: "We discussed forgiveness and discipleship", respectFeatureFlags: false)
        let topic = try #require(entities.first { $0.type == .topic })
        let actions = SmartMessageLocalDetector.actions(for: topic, context: .local(messageId: "m4", surface: "test"))
        #expect(actions.contains { $0.actionType == .searchRelated })
        #expect(actions.contains { $0.actionType == .startStudyMode })
        #expect(actions.contains { $0.actionType == .openKnowledgeGraph })
    }

    @Test func unicodeScriptureRangesUseCharacterOffsets() async throws {
        let entities = SmartMessageLocalDetector.detect(in: "🙏 Read Romans 8:28 tonight", respectFeatureFlags: false)
        let scripture = try #require(entities.first { $0.type == .scriptureReference })
        #expect(scripture.range.start == 7)
        #expect(scripture.range.length == "Romans 8:28".count)
    }

    @Test func detectedScriptureReferencesParseForSelahReader() async throws {
        let entities = SmartMessageLocalDetector.detect(in: "Read 1 John 4:8 and Romans 8:28-30", respectFeatureFlags: false)
        let references = entities.filter { $0.type == .scriptureReference }
        #expect(references.contains { SelahScriptureReferenceParser.parse($0.normalizedValue)?.displayString == "1 John 4:8" })
        #expect(references.contains { SelahScriptureReferenceParser.parse($0.normalizedValue)?.displayString == "Romans 8:28-30" })
    }

    @Test func smartSearchRankingModeLabelsVectorAndFallbackHonestly() async throws {
        #expect(SmartSearchRankingMode.vector.label == "Semantic vector ranking")
        #expect(SmartSearchRankingMode.keywordFallback.explanation.contains("Keyword fallback"))
    }

    @Test func repeatedDetectionUsesStableCachedEntities() async throws {
        let first = SmartMessageLocalDetector.detect(in: "Read John 3:16 and pray tonight", respectFeatureFlags: false)
        let second = SmartMessageLocalDetector.detect(in: "Read John 3:16 and pray tonight", respectFeatureFlags: false)
        #expect(first == second)
    }
}
