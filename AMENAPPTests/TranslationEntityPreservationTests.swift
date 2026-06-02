// TranslationEntityPreservationTests.swift
// AMENAPPTests
//
// Verifies MeaningAwareTranslationService.extractPreservedEntities() correctly
// identifies and isolates entities that must survive LLM translation unchanged.

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

// MARK: - TranslationEntityPreservationTests

@MainActor
@Suite("TranslationEntityPreservation")
struct TranslationEntityPreservationTests {

    private let service = MeaningAwareTranslationService.shared

    // MARK: 1. Bible verse references

    @Test("Single verse reference is detected")
    func singleVerseReference() {
        let entities = service.extractPreservedEntities(from: "As it says in John 3:16, God so loved the world.")
        let verses = entities.filter { $0.type == .verseReference }
        #expect(!verses.isEmpty)
        #expect(verses.first?.originalText.contains("3:16") == true)
    }

    @Test("Range verse reference is detected")
    func rangeVerseReference() {
        let entities = service.extractPreservedEntities(from: "Read Romans 8:28-30 for comfort.")
        let verses = entities.filter { $0.type == .verseReference }
        #expect(!verses.isEmpty)
    }

    @Test("Numbered book verse is detected")
    func numberedBookVerse() {
        let entities = service.extractPreservedEntities(from: "1 Corinthians 13:4 describes love.")
        let verses = entities.filter { $0.type == .verseReference }
        #expect(!verses.isEmpty)
    }

    // MARK: 2. Bible translation abbreviations

    @Test("KJV translation abbreviation is detected")
    func kjvAbbreviation() {
        let entities = service.extractPreservedEntities(from: "I prefer the KJV translation.")
        let translations = entities.filter { $0.type == .bibleTranslation }
        #expect(!translations.isEmpty)
        #expect(translations.first?.originalText == "KJV")
    }

    @Test("NIV and ESV in same text both detected")
    func multipleTranslationAbbreviations() {
        let entities = service.extractPreservedEntities(from: "Both NIV and ESV render this clearly.")
        let translations = entities.filter { $0.type == .bibleTranslation }
        #expect(translations.count == 2)
    }

    @Test("Non-abbreviation word is not misidentified as translation")
    func noFalseTranslationMatch() {
        let entities = service.extractPreservedEntities(from: "This is a normal sentence.")
        let translations = entities.filter { $0.type == .bibleTranslation }
        #expect(translations.isEmpty)
    }

    // MARK: 3. @mentions

    @Test("Single mention is detected")
    func singleMention() {
        let entities = service.extractPreservedEntities(from: "Great post @pastor_john!")
        let mentions = entities.filter { $0.type == .mention }
        #expect(!mentions.isEmpty)
        #expect(mentions.first?.originalText == "@pastor_john")
    }

    @Test("Multiple mentions are all detected")
    func multipleMentions() {
        let entities = service.extractPreservedEntities(from: "Thanks @alice and @bob for the encouragement.")
        let mentions = entities.filter { $0.type == .mention }
        #expect(mentions.count == 2)
    }

    // MARK: 4. Hashtags

    @Test("Single hashtag is detected")
    func singleHashtag() {
        let entities = service.extractPreservedEntities(from: "Blessed day #FaithFirst")
        let tags = entities.filter { $0.type == .hashtag }
        #expect(!tags.isEmpty)
        #expect(tags.first?.originalText == "#FaithFirst")
    }

    @Test("Multiple hashtags are all detected")
    func multipleHashtags() {
        let entities = service.extractPreservedEntities(from: "#Worship #Prayer #Faith together.")
        let tags = entities.filter { $0.type == .hashtag }
        #expect(tags.count == 3)
    }

    // MARK: 5. URLs

    @Test("HTTPS URL is detected")
    func httpsURL() {
        let entities = service.extractPreservedEntities(from: "Check out https://example.com/page for more.")
        let urls = entities.filter { $0.type == .url }
        #expect(!urls.isEmpty)
        #expect(urls.first?.originalText.hasPrefix("https://") == true)
    }

    // MARK: 6. Placeholder generation

    @Test("Each entity gets a unique placeholder")
    func placeholdersAreUnique() {
        let entities = service.extractPreservedEntities(from: "@alice @bob #Faith John 3:16")
        let placeholders = entities.map { $0.placeholder }
        let uniquePlaceholders = Set(placeholders)
        #expect(placeholders.count == uniquePlaceholders.count)
    }

    @Test("Placeholder contains entity type token")
    func placeholderContainsTypeToken() {
        let entities = service.extractPreservedEntities(from: "@pastor_john")
        let mention = entities.first { $0.type == .mention }
        #expect(mention?.placeholder.contains("MENTION") == true)
    }

    // MARK: 7. Mixed content

    @Test("Text with verse, mention, hashtag, and URL captures all entity types")
    func mixedContentAllCaptured() {
        let text = "Love John 3:16 (ESV) @pastor #Faith https://amen.app/post/123"
        let entities = service.extractPreservedEntities(from: text)
        let types = Set(entities.map { $0.type })
        #expect(types.contains(.verseReference))
        #expect(types.contains(.bibleTranslation))
        #expect(types.contains(.mention))
        #expect(types.contains(.hashtag))
        #expect(types.contains(.url))
    }

    @Test("Empty string returns no entities")
    func emptyStringProducesNoEntities() {
        let entities = service.extractPreservedEntities(from: "")
        #expect(entities.isEmpty)
    }

    @Test("Plain prose with no special tokens returns no entities")
    func plainProseProducesNoEntities() {
        let entities = service.extractPreservedEntities(from: "God is good all the time.")
        #expect(entities.isEmpty)
    }

    // MARK: 8. Reinsertion round-trip

    @Test("reinsertEntities restores a modified placeholder back to original text")
    func reinsertionRestoresEntity() {
        let original = "Blessed by John 3:16 today."
        let entities = service.extractPreservedEntities(from: original)
        guard let verse = entities.first(where: { $0.type == .verseReference }) else {
            Issue.record("No verse entity found in test input")
            return
        }
        // Simulate LLM replacing original text with placeholder
        let simulatedLLMOutput = "Blessed by \(verse.placeholder) today."
        let restored = service.reinsertEntities(entities, into: simulatedLLMOutput, original: original)
        #expect(restored.contains(verse.originalText))
        #expect(!restored.contains(verse.placeholder))
    }

    @Test("reinsertEntities is a no-op when LLM preserved original text")
    func reinsertionIsNoopWhenLLMPreserved() {
        let original = "@pastor the meeting is at 5pm."
        let entities = service.extractPreservedEntities(from: original)
        // Simulate LLM keeping the mention unchanged
        let llmOutput = "@pastor la reunión es a las 5pm."
        let result = service.reinsertEntities(entities, into: llmOutput, original: original)
        #expect(result == llmOutput)
    }
}

#endif
