import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@Suite("AMEN Feed Context Labels")
@MainActor
struct AmenFeedContextLabelTests {
    private func makeLabel(
        id: String = UUID().uuidString,
        type: AmenFeedContextType = .inConversation,
        title: String = "Faith during waiting",
        confidence: Double = 0.9,
        topicId: String? = "faith_waiting",
        expiresAt: Date? = nil,
        isSensitive: Bool = false,
        destination: AmenFeedContextDestination = .init(type: .topicFeed, id: "faith_waiting")
    ) -> AmenFeedContextLabel {
        AmenFeedContextLabel(
            id: id,
            type: type,
            title: title,
            reason: "This connects with topics you've shown interest in.",
            confidence: confidence,
            priority: type.priorityWeight,
            destination: destination,
            topicId: topicId,
            verseRef: nil,
            churchId: nil,
            communityId: nil,
            expiresAt: expiresAt,
            isSensitive: isSensitive,
            isDismissible: true,
            analyticsId: "analytics-\(id)"
        )
    }

    private func makePost(id: String, label: AmenFeedContextLabel? = nil) -> Post {
        Post(
            id: UUID(),
            firebaseId: id,
            authorId: "author-\(id)",
            authorName: "Author \(id)",
            authorUsername: "author\(id)",
            authorInitials: "AU",
            authorProfileImageURL: nil,
            timeAgo: "1m",
            content: "Post \(id)",
            category: .openTable,
            topicTag: label?.topicId,
            visibility: .everyone,
            allowComments: true,
            commentPermissions: .everyone,
            createdAt: Date(),
            amenCount: 0,
            lightbulbCount: 0,
            commentCount: 0,
            repostCount: 0,
            feedContext: label
        )
    }

    private func makeStore() -> ContextLabelPreferenceStore {
        let store = ContextLabelPreferenceStore.shared
        store.replaceStateForTesting()
        return store
    }

    @Test("Confidence threshold suppresses weak labels")
    func confidenceThreshold() {
        let post = makePost(id: "1", label: makeLabel(confidence: 0.6))
        #expect(AmenFeedContextResolver.isEligible(label: post.feedContext!, for: post, preferences: makeStore()) == false)
    }

    @Test("Expired labels do not render")
    func expirationLogic() {
        let post = makePost(id: "1", label: makeLabel(expiresAt: Date().addingTimeInterval(-60)))
        #expect(AmenFeedContextResolver.isEligible(label: post.feedContext!, for: post, preferences: makeStore()) == false)
    }

    @Test("Duplicate topic suppression")
    func duplicateTopicSuppression() {
        let first = makePost(id: "1", label: makeLabel(id: "a", topicId: "romans_8"))
        let second = makePost(id: "2", label: makeLabel(id: "b", topicId: "romans_8"))
        let result = AmenFeedContextResolver.resolveVisibleLabels(for: [first, second], preferences: makeStore())
        #expect(result[first.contextStableId] != nil)
        #expect(result[second.contextStableId] == nil)
    }

    @Test("Adjacent labels are suppressed")
    func adjacentSuppression() {
        let first = makePost(id: "1", label: makeLabel(id: "a", topicId: "romans_8"))
        let second = makePost(id: "2", label: makeLabel(id: "b", topicId: "healing"))
        let result = AmenFeedContextResolver.resolveVisibleLabels(for: [first, second], preferences: makeStore())
        #expect(result.count == 1)
    }

    @Test("Muted topic suppression")
    func mutedTopicSuppression() {
        let store = makeStore()
        store.replaceStateForTesting(mutedContextTopicIds: ["forgiveness"])
        let label = makeLabel(topicId: "forgiveness")
        let post = makePost(id: "1", label: label)
        #expect(AmenFeedContextResolver.isEligible(label: label, for: post, preferences: store) == false)
    }

    @Test("Muted type suppression")
    func mutedTypeSuppression() {
        let store = makeStore()
        store.replaceStateForTesting(mutedContextTypes: [AmenFeedContextType.scriptureFocus.rawValue])
        let label = makeLabel(type: .scriptureFocus)
        let post = makePost(id: "1", label: label)
        #expect(AmenFeedContextResolver.isEligible(label: label, for: post, preferences: store) == false)
    }

    @Test("Sensitive topic suppression")
    func sensitiveTopicSuppression() {
        let label = makeLabel(type: .sharedInYourCircles, confidence: 0.95, isSensitive: true)
        let post = makePost(id: "1", label: label)
        #expect(AmenFeedContextResolver.isEligible(label: label, for: post, preferences: makeStore()) == false)
    }

    @Test("Destination fallback uses why-this-appeared")
    func destinationFallback() {
        let label = makeLabel(destination: .init(type: .none, id: nil))
        #expect(label.effectiveDestination.type == .whyThisAppeared)
    }

    @Test("Malformed metadata is suppressed")
    func malformedMetadata() {
        let label = makeLabel(title: "")
        let post = makePost(id: "1", label: label)
        #expect(AmenFeedContextResolver.isEligible(label: label, for: post, preferences: makeStore()) == false)
    }

    @Test("Disabled preference suppresses all labels")
    func disabledPreference() {
        let store = makeStore()
        store.replaceStateForTesting(contextualLabelsDisabled: true)
        let post = makePost(id: "1", label: makeLabel())
        let result = AmenFeedContextResolver.resolveVisibleLabels(for: [post], preferences: store)
        #expect(result.isEmpty)
    }

    @Test("Analytics event names are stable")
    func analyticsEventGeneration() {
        let card = PostCard(post: makePost(id: "1"))
        #expect(card.analyticsEventName(for: .showLess) == "context_label_show_less")
        #expect(card.analyticsEventName(for: .hideAll) == "context_label_hide_all")
    }
}
#endif
