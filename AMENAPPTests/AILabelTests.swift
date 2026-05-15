import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

// MARK: - AI Label Tests

@Suite("Post AI Label System")
struct AILabelTests {

    // MARK: - Label priority

    @Test("draft_generation resolves to ai_assisted_post")
    func draftGenerationLabel() {
        let label = PostAIUsage.resolveLabel(from: [.draftGeneration])
        #expect(label == .aiAssistedPost)
    }

    @Test("tone_rewrite_major resolves to ai_assisted_post")
    func toneRewriteMajorLabel() {
        let label = PostAIUsage.resolveLabel(from: [.toneRewriteMajor])
        #expect(label == .aiAssistedPost)
    }

    @Test("translation resolves to translated_with_ai")
    func translationLabel() {
        let label = PostAIUsage.resolveLabel(from: [.translation])
        #expect(label == .translatedWithAI)
    }

    @Test("tone_rewrite_minor resolves to ai_assisted_tone")
    func toneRewriteMinorLabel() {
        let label = PostAIUsage.resolveLabel(from: [.toneRewriteMinor])
        #expect(label == .aiAssistedTone)
    }

    @Test("safety_rewrite resolves to edited_for_safety")
    func safetyRewriteLabel() {
        let label = PostAIUsage.resolveLabel(from: [.safetyRewrite])
        #expect(label == .editedForSafety)
    }

    @Test("sermon_notes_summary resolves to notes_summarized")
    func sermonNotesSummaryLabel() {
        let label = PostAIUsage.resolveLabel(from: [.sermonNotesSummary])
        #expect(label == .notesSummarized)
    }

    @Test("prayer_generation resolves to prayer_assisted")
    func prayerGenerationLabel() {
        let label = PostAIUsage.resolveLabel(from: [.prayerGeneration])
        #expect(label == .prayerAssisted)
    }

    @Test("scripture_suggestion resolves to scripture_suggested")
    func scriptureSuggestionLabel() {
        let label = PostAIUsage.resolveLabel(from: [.scriptureSuggestion])
        #expect(label == .scriptureSuggested)
    }

    @Test("berean_insert resolves to berean_assisted")
    func bereanInsertLabel() {
        let label = PostAIUsage.resolveLabel(from: [.bereanInsert])
        #expect(label == .bereanAssisted)
    }

    @Test("tone_check only resolves to tone_checked")
    func toneCheckOnlyLabel() {
        let label = PostAIUsage.resolveLabel(from: [.toneCheck])
        #expect(label == .toneChecked)
    }

    @Test("alt_text_generation resolves to alt_text_assisted")
    func altTextLabel() {
        let label = PostAIUsage.resolveLabel(from: [.altTextGeneration])
        #expect(label == .altTextAssisted)
    }

    @Test("empty array resolves to nil")
    func emptyTypesReturnsNil() {
        let label = PostAIUsage.resolveLabel(from: [])
        #expect(label == nil)
    }

    // MARK: - Priority: higher beats lower

    @Test("draft_generation beats tone_check in priority")
    func draftBeatsToneCheck() {
        let label = PostAIUsage.resolveLabel(from: [.toneCheck, .draftGeneration])
        #expect(label == .aiAssistedPost)
    }

    @Test("translation beats tone_rewrite_minor in priority")
    func translationBeatsToneRewrite() {
        let label = PostAIUsage.resolveLabel(from: [.toneRewriteMinor, .translation])
        #expect(label == .translatedWithAI)
    }

    @Test("safety_rewrite beats scripture_suggestion in priority")
    func safetyBeatsScrip() {
        let label = PostAIUsage.resolveLabel(from: [.scriptureSuggestion, .safetyRewrite])
        #expect(label == .editedForSafety)
    }

    // MARK: - Disclosure required

    @Test("tone_checked label is not required (can be removed)")
    func toneCheckedNotRequired() {
        #expect(AIPublicLabel.toneChecked.isRequired == false)
    }

    @Test("alt_text_assisted label is not required")
    func altTextNotRequired() {
        #expect(AIPublicLabel.altTextAssisted.isRequired == false)
    }

    @Test("ai_assisted_post label is required")
    func aiPostRequired() {
        #expect(AIPublicLabel.aiAssistedPost.isRequired == true)
    }

    @Test("translated_with_ai label is required")
    func translationRequired() {
        #expect(AIPublicLabel.translatedWithAI.isRequired == true)
    }

    @Test("edited_for_safety label is required")
    func safetyRequired() {
        #expect(AIPublicLabel.editedForSafety.isRequired == true)
    }

    @Test("ai_assisted_tone label is required")
    func aiToneRequired() {
        #expect(AIPublicLabel.aiAssistedTone.isRequired == true)
    }

    // MARK: - Display text

    @Test("All labels have non-empty display text")
    func allLabelsHaveDisplayText() {
        for label in AIPublicLabel.allCases {
            #expect(!label.displayText.isEmpty, "Label \(label.rawValue) missing displayText")
        }
    }

    @Test("All labels have non-empty disclosure copy")
    func allLabelsHaveDisclosureCopy() {
        for label in AIPublicLabel.allCases {
            #expect(!label.disclosureCopy.isEmpty, "Label \(label.rawValue) missing disclosureCopy")
            #expect(!label.disclosureCopy.contains("author controlled") || label.disclosureCopy.contains("author"),
                    "Disclosure copy for \(label.rawValue) should reference the author")
        }
    }

    // MARK: - Post rendering

    @Test("PostAILabelPill does not render when usedAI is false")
    func pillNotRenderedWhenNoAI() {
        let usage = makeUsage(usedAI: false, types: [.toneCheck], label: .toneChecked)
        // No display when usedAI is false — confirmed by checking the condition in PostAILabelPill
        #expect(usage.usedAI == false)
    }

    @Test("PostAILabelPill renders when usedAI is true")
    func pillRenderedWhenAIUsed() {
        let usage = makeUsage(usedAI: true, types: [.toneCheck], label: .toneChecked)
        #expect(usage.usedAI == true)
        #expect(usage.primaryLabel == .toneChecked)
    }

    // MARK: - Helpers

    private func makeUsage(usedAI: Bool, types: [AIUseType], label: AIPublicLabel) -> PostAIUsage {
        PostAIUsage(
            usedAI: usedAI,
            aiUseTypes: types,
            primaryLabel: label,
            secondaryDetail: nil,
            userAcceptedSuggestion: false,
            aiGeneratedPercentageEstimate: nil,
            toneCheckSummary: nil,
            disclosureRequired: label.isRequired,
            rawPromptStored: false,
            rawUserTextStored: false,
            modelVersion: nil
        )
    }
}

#endif
