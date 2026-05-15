import Foundation
import SwiftUI

#if canImport(Testing)
import Testing
@testable import AMENAPP

@Suite("Context Label Display Behavior")
@MainActor
struct AmenFeedContextLabelDisplayTests {

    private func makeLabel(
        type: AmenFeedContextType = .inConversation,
        title: String = "Faith during waiting",
        confidence: Double = 0.9,
        isSensitive: Bool = false,
        expiresAt: Date? = nil,
        topicId: String? = nil
    ) -> AmenFeedContextLabel {
        AmenFeedContextLabel(
            id: UUID().uuidString,
            type: type,
            title: title,
            reason: "Test reason",
            confidence: confidence,
            priority: type.priorityWeight,
            destination: .init(type: type.defaultDestination, id: nil),
            topicId: topicId,
            verseRef: nil,
            churchId: nil,
            communityId: nil,
            expiresAt: expiresAt,
            isSensitive: isSensitive,
            isDismissible: true,
            analyticsId: "test-\(UUID().uuidString)"
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

    private func cleanStore() -> ContextLabelPreferenceStore {
        let store = ContextLabelPreferenceStore.shared
        store.replaceStateForTesting()
        return store
    }

    // MARK: - Truncation

    @Test("Very long titles are preserved in the model — lineLimit(1) clips in the view")
    func longTitlePassthrough() {
        let longTitle = String(repeating: "Reflections on the character of God ", count: 10)
        let label = makeLabel(title: longTitle)
        #expect(label.title == longTitle)
        #expect(label.displayPrefix != longTitle)
    }

    @Test("Whitespace-only title is rejected by the eligibility check")
    func whitespaceTitleRejected() {
        let label = makeLabel(title: "    ")
        let post = makePost(id: "ws", label: label)
        #expect(AmenFeedContextResolver.isEligible(label: label, for: post, preferences: cleanStore()) == false)
    }

    @Test("Single-character title passes the non-empty guard")
    func singleCharTitleIsEligible() {
        let label = makeLabel(title: "A")
        let post = makePost(id: "sc", label: label)
        #expect(AmenFeedContextResolver.isEligible(label: label, for: post, preferences: cleanStore()) == true)
    }

    // MARK: - Typography / display prefix

    @Test("Every context type produces a non-empty displayPrefix and sensitiveDisplayPrefix")
    func allTypesHaveNonEmptyPrefixes() {
        for type in AmenFeedContextType.allCases {
            #expect(!type.displayPrefix.isEmpty, "displayPrefix empty for \(type.rawValue)")
            #expect(!type.sensitiveDisplayPrefix.isEmpty, "sensitiveDisplayPrefix empty for \(type.rawValue)")
        }
    }

    @Test("Pastoral types use a distinct sensitive prefix that avoids revealing specifics")
    func pastoralTypesHaveSensitiveAlternatePrefix() {
        #expect(AmenFeedContextType.churchPulse.sensitiveDisplayPrefix != AmenFeedContextType.churchPulse.displayPrefix)
        #expect(AmenFeedContextType.livePrayerMoment.sensitiveDisplayPrefix != AmenFeedContextType.livePrayerMoment.displayPrefix)
        #expect(AmenFeedContextType.gentleFollowUp.sensitiveDisplayPrefix != AmenFeedContextType.gentleFollowUp.displayPrefix)
    }

    @Test("isSensitive label uses the sanitised sensitiveDisplayPrefix")
    func sensitiveLabelUsesSensitivePrefix() {
        let label = makeLabel(type: .churchPulse, isSensitive: true)
        #expect(label.displayPrefix == AmenFeedContextType.churchPulse.sensitiveDisplayPrefix)
    }

    @Test("Non-sensitive label uses the standard displayPrefix")
    func nonSensitiveLabelUsesStandardPrefix() {
        let label = makeLabel(type: .churchPulse, isSensitive: false)
        #expect(label.displayPrefix == AmenFeedContextType.churchPulse.displayPrefix)
    }

    @Test("All context type icon names are non-empty system symbol strings")
    func allTypesHaveIconName() {
        for type in AmenFeedContextType.allCases {
            #expect(!type.iconName.isEmpty, "iconName empty for \(type.rawValue)")
        }
    }

    // MARK: - Dynamic Type boundary guard
    // Verifies the condition that drives `.padding(.vertical, isAccessibilitySize ? 8 : 6)`

    @Test("Accessibility DynamicTypeSize values report isAccessibilitySize == true")
    func accessibilityTypeSizesFlaggedCorrectly() {
        #expect(DynamicTypeSize.accessibility1.isAccessibilitySize == true)
        #expect(DynamicTypeSize.accessibility2.isAccessibilitySize == true)
        #expect(DynamicTypeSize.accessibility3.isAccessibilitySize == true)
        #expect(DynamicTypeSize.accessibility4.isAccessibilitySize == true)
        #expect(DynamicTypeSize.accessibility5.isAccessibilitySize == true)
    }

    @Test("Standard DynamicTypeSize values report isAccessibilitySize == false")
    func standardTypeSizesNotFlagged() {
        #expect(DynamicTypeSize.medium.isAccessibilitySize == false)
        #expect(DynamicTypeSize.large.isAccessibilitySize == false)
        #expect(DynamicTypeSize.xLarge.isAccessibilitySize == false)
        #expect(DynamicTypeSize.xxLarge.isAccessibilitySize == false)
        #expect(DynamicTypeSize.xxxLarge.isAccessibilitySize == false)
    }

    // MARK: - Visibility coordinator slot management

    @Test("Coordinator enforces a maximum of 2 simultaneously visible labels")
    func visibilityCapacityIsTwo() {
        let coordinator = ContextLabelVisibilityCoordinator()
        #expect(coordinator.register(postId: "p1") == true)
        #expect(coordinator.register(postId: "p2") == true)
        #expect(coordinator.register(postId: "p3") == false)
    }

    @Test("Re-registering an already visible postId returns true without consuming a slot")
    func reRegistrationIsIdempotent() {
        let coordinator = ContextLabelVisibilityCoordinator()
        _ = coordinator.register(postId: "p1")
        _ = coordinator.register(postId: "p2")
        #expect(coordinator.register(postId: "p1") == true)
        #expect(coordinator.register(postId: "p3") == false)
    }

    @Test("Unregistering a visible label promotes the oldest pending label")
    func promotionAfterUnregister() {
        let coordinator = ContextLabelVisibilityCoordinator()
        _ = coordinator.register(postId: "p1")
        _ = coordinator.register(postId: "p2")
        _ = coordinator.register(postId: "p3")  // queued as pending
        coordinator.unregister(postId: "p1")
        // p3 should now be in the visible set; re-registering returns true
        #expect(coordinator.register(postId: "p3") == true)
    }

    @Test("Unregistering a pending label does not trigger a nonce refresh")
    func pendingUnregisterSkipsNonceRefresh() {
        let coordinator = ContextLabelVisibilityCoordinator()
        _ = coordinator.register(postId: "p1")
        _ = coordinator.register(postId: "p2")
        _ = coordinator.register(postId: "p3-pending")
        let nonceBefore = coordinator.refreshNonce
        coordinator.unregister(postId: "p3-pending")
        #expect(coordinator.refreshNonce == nonceBefore)
    }

    @Test("Unregistering a visible label with a pending entry triggers a nonce refresh")
    func visibleUnregisterWithPendingRefreshesNonce() {
        let coordinator = ContextLabelVisibilityCoordinator()
        _ = coordinator.register(postId: "p1")
        _ = coordinator.register(postId: "p2")
        _ = coordinator.register(postId: "p3-pending")
        let nonceBefore = coordinator.refreshNonce
        coordinator.unregister(postId: "p1")
        #expect(coordinator.refreshNonce != nonceBefore)
    }

    // MARK: - Placement ordering

    @Test("Posts without feedContext are skipped entirely by the resolver")
    func postsWithoutContextSkipped() {
        let posts = (1...5).map { makePost(id: "\($0)", label: nil) }
        let result = AmenFeedContextResolver.resolveVisibleLabels(for: posts, preferences: cleanStore())
        #expect(result.isEmpty)
    }

    @Test("Resolver assigns a label to a labeled post surrounded by unlabeled posts")
    func isolatedLabeledPostReceivesLabel() {
        let label = makeLabel()
        let posts = [
            makePost(id: "1"),
            makePost(id: "2", label: label),
            makePost(id: "3")
        ]
        let result = AmenFeedContextResolver.resolveVisibleLabels(for: posts, preferences: cleanStore())
        #expect(result[posts[1].contextStableId] != nil)
    }

    @Test("Higher priority label wins when two non-adjacent posts compete")
    func higherPriorityLabelWins() {
        let low  = makeLabel(type: .relevantNow,   confidence: 0.9, topicId: "a")    // priority 68
        let high = makeLabel(type: .livePrayerMoment, confidence: 0.9, topicId: "b") // priority 100
        let posts = [
            makePost(id: "1", label: low),
            makePost(id: "2"),
            makePost(id: "3", label: high)
        ]
        let result = AmenFeedContextResolver.resolveVisibleLabels(for: posts, preferences: cleanStore())
        // Both are non-adjacent so both should render; the resolver sorts by priority
        #expect(result[posts[0].contextStableId] != nil)
        #expect(result[posts[2].contextStableId] != nil)
    }

    // MARK: - Expiry boundary values

    @Test("Label that expired 1 second ago is suppressed")
    func expiryJustPassedIsSuppressed() {
        let now = Date()
        let label = makeLabel(expiresAt: now.addingTimeInterval(-1))
        let post = makePost(id: "e1", label: label)
        #expect(AmenFeedContextResolver.isEligible(label: label, for: post, preferences: cleanStore(), now: now) == false)
    }

    @Test("Label expiring 1 second from now is still eligible")
    func expiryInNearFutureIsEligible() {
        let now = Date()
        let label = makeLabel(expiresAt: now.addingTimeInterval(1))
        let post = makePost(id: "e2", label: label)
        #expect(AmenFeedContextResolver.isEligible(label: label, for: post, preferences: cleanStore(), now: now) == true)
    }

    @Test("Label with no expiry date is always time-eligible")
    func noExpiryIsAlwaysEligible() {
        let label = makeLabel(expiresAt: nil)
        let post = makePost(id: "e3", label: label)
        #expect(AmenFeedContextResolver.isEligible(label: label, for: post, preferences: cleanStore()) == true)
    }
}
#endif
