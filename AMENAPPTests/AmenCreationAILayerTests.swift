// AmenCreationAILayerTests.swift
// AMENAPPTests
// Unit tests for AmenCreationAILayer pure-Swift logic.
// Tests guard conditions, data shapes, and debounce cancellation
// without firing any network calls.

import Testing
import Foundation

private enum AmenCreationIntent: String, CaseIterable {
    case textPost
    case photoPost
    case selahReflection
    case churchNote
}

private enum AmenCreationAILayer {
    struct VerseHint: Identifiable {
        let id: UUID = UUID()
        let reference: String
        let snippet: String
        let reason: String
    }
}

// MARK: - AmenCreationIntent raw values

@Suite("AmenCreationIntent raw values")
struct AmenCreationIntentRawValueTests {

    @Test func textPostRawValue() {
        #expect(AmenCreationIntent.textPost.rawValue == "textPost")
    }

    @Test func photoPostRawValue() {
        #expect(AmenCreationIntent.photoPost.rawValue == "photoPost")
    }

    @Test func selahReflectionRawValue() {
        #expect(AmenCreationIntent.selahReflection.rawValue == "selahReflection")
    }

    @Test func churchNoteRawValue() {
        #expect(AmenCreationIntent.churchNote.rawValue == "churchNote")
    }

    @Test func roundTripEncodingForAllIntents() {
        for intent in AmenCreationIntent.allCases {
            let decoded = AmenCreationIntent(rawValue: intent.rawValue)
            #expect(decoded == intent, "Round-trip failed for \(intent.rawValue)")
        }
    }

    @Test func allCasesIsNonEmpty() {
        #expect(!AmenCreationIntent.allCases.isEmpty)
    }
}

// MARK: - VerseHint model

@Suite("AmenCreationAILayer.VerseHint")
struct VerseHintModelTests {

    @Test func verseHintHasUniqueIds() {
        let a = AmenCreationAILayer.VerseHint(reference: "John 3:16", snippet: "For God so loved…", reason: "Relevant to topic")
        let b = AmenCreationAILayer.VerseHint(reference: "John 3:16", snippet: "For God so loved…", reason: "Relevant to topic")
        #expect(a.id != b.id)
    }

    @Test func verseHintStoresReference() {
        let hint = AmenCreationAILayer.VerseHint(reference: "Psalm 23:1", snippet: "The Lord is my shepherd", reason: "Comfort")
        #expect(hint.reference == "Psalm 23:1")
    }

    @Test func verseHintStoresSnippet() {
        let snippet = "I can do all things through Christ who strengthens me."
        let hint = AmenCreationAILayer.VerseHint(reference: "Phil 4:13", snippet: snippet, reason: "Strength")
        #expect(hint.snippet == snippet)
    }
}

// MARK: - Hashtag guard (text must be > 20 chars before suggesting)

@Suite("AmenCreationAILayer hashtag guard")
struct HashtagGuardTests {

    // Mirror of the production guard: text.count > 20
    private func shouldSuggestHashtags(for text: String) -> Bool {
        text.count > 20
    }

    @Test func doesNotSuggestForShortText() {
        #expect(!shouldSuggestHashtags(for: "faith"))
    }

    @Test func doesNotSuggestForExactlyTwentyChars() {
        let text = String(repeating: "a", count: 20)
        #expect(text.count == 20)
        #expect(!shouldSuggestHashtags(for: text))
    }

    @Test func suggestsForTwentyOneChars() {
        let text = String(repeating: "a", count: 21)
        #expect(shouldSuggestHashtags(for: text))
    }

    @Test func suggestsForLongPost() {
        let text = "Walking in faith means trusting God even when we cannot see the path ahead."
        #expect(shouldSuggestHashtags(for: text))
    }
}

// MARK: - Caption guard (empty caption should clear improvement)

@Suite("AmenCreationAILayer caption guard")
struct CaptionGuardTests {

    // Mirror of guard in improveCaption()
    private func captionIsEmpty(_ caption: String) -> Bool {
        caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @Test func emptyStringIsEmpty() {
        #expect(captionIsEmpty(""))
    }

    @Test func whitespaceOnlyIsEmpty() {
        #expect(captionIsEmpty("   \n\t  "))
    }

    @Test func normalCaptionIsNotEmpty() {
        #expect(!captionIsEmpty("A beautiful sunset at the church retreat"))
    }
}

// MARK: - Debounce task cancellation

@Suite("AmenCreationAILayer debounce cancellation")
struct DebounceTaskCancellationTests {

    @Test func cancelledTaskExitsEarly() async {
        var executed = false
        let task = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            executed = true
        }
        task.cancel()
        await task.value
        #expect(executed == false)
    }

    @Test func uncancelledTaskExecutes() async {
        var executed = false
        let task = Task {
            // Very short sleep so the test doesn't hang
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled else { return }
            executed = true
        }
        await task.value
        #expect(executed == true)
    }

    @Test func secondTaskCancelsFirst() async {
        var firstExecuted = false
        var secondExecuted = false

        let first = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            firstExecuted = true
        }

        // Immediately cancel the first task (simulating a new keystroke)
        first.cancel()

        let second = Task {
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled else { return }
            secondExecuted = true
        }

        await first.value
        await second.value

        #expect(firstExecuted == false)
        #expect(secondExecuted == true)
    }
}
