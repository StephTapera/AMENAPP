import Testing
@testable import AMENAPP

@Suite("Amen AI task policy")
struct AmenAITaskPolicyTests {
    @Test func prayerAndPrivateMessagesRequireConsentAndBackendOnly() {
        let result = AmenAITaskPolicy.evaluateContent(
            "Please pray for me about this private message thread.",
            surface: "smart_message_summary"
        )

        #expect(result.categories.contains(.prayer))
        #expect(result.categories.contains(.privateMessage))
        #expect(result.requiresExplicitConsent)
        #expect(result.requiresBackendOnly)
    }

    @Test func crisisAndMinorContentEscalatesToRestrictedRisk() {
        let result = AmenAITaskPolicy.evaluateContent(
            "A 15 year old said they might hurt myself tonight.",
            surface: "berean_chat"
        )

        #expect(result.categories.contains(.minors))
        #expect(result.categories.contains(.crisis))
        #expect(AmenAITaskPolicy.minimumRisk(for: .bereanQuickAnswer, contentPolicy: result) == .restricted)
    }

    @Test func lowRiskCaptionSuggestionStaysLowRiskWhenContentIsClear() {
        let result = AmenAITaskPolicy.evaluateContent(
            "Write a caption for a photo of sunrise before Sunday service.",
            surface: "post_caption_suggestion"
        )

        #expect(result == .clear)
        #expect(AmenAITaskPolicy.minimumRisk(for: .postCaptionSuggestion, contentPolicy: result) == .low)
    }

    @Test func backendOnlyTasksCannotBeDirectClientCandidates() {
        #expect(AmenAITaskType.moderation.requiresBackendOnly)
        #expect(AmenAITaskType.crisis.requiresBackendOnly)
        #expect(AmenAITaskType.feedRanking.requiresBackendOnly)
        #expect(AmenAITaskType.creatorMonetization.requiresBackendOnly)
        #expect(AmenAITaskType.finalPublishDecision.requiresBackendOnly)
        #expect(AmenAITaskType.bereanDeepStudy.requiresBackendOnly)
    }
}
