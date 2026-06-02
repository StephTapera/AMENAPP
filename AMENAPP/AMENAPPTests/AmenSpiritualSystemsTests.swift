import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@Suite("Amen Spiritual Systems")
@MainActor
struct AmenSpiritualSystemsTests {
    private let service = AmenSpiritualSystemsService.shared

    private func makePost(
        content: String,
        category: Post.PostCategory = .openTable,
        prayTapsCount: Int = 0,
        encouragedCount: Int = 0,
        savesCount: Int = 0,
        prayerStatus: String? = nil,
        isAnsweredPrayer: Bool = false,
        threadId: String? = nil
    ) -> Post {
        Post(
            id: UUID(),
            firebaseId: UUID().uuidString,
            authorId: "author",
            authorName: "Author",
            authorUsername: "author",
            authorInitials: "AU",
            authorProfileImageURL: nil,
            timeAgo: "1m",
            content: content,
            category: category,
            topicTag: nil,
            visibility: .everyone,
            allowComments: true,
            commentPermissions: .everyone,
            createdAt: Date(),
            amenCount: 0,
            lightbulbCount: 0,
            commentCount: 0,
            repostCount: 0,
            prayerStatus: prayerStatus,
            isAnsweredPrayer: isAnsweredPrayer,
            savesCount: savesCount,
            prayTapsCount: prayTapsCount,
            encouragedCount: encouragedCount,
            threadId: threadId
        )
    }

    @Test("Compose analyzer detects prayer and suggestions")
    func prayerIntentDetection() {
        let result = service.analyzeComposer(text: "Please pray for me this week.")
        #expect(result.intent == .prayer)
        #expect(result.suggestions.isEmpty == false)
    }

    @Test("Compose analyzer triggers discernment gate for shame language")
    func discernmentGateDetection() {
        let result = service.analyzeComposer(text: "You should be ashamed of yourself.")
        #expect(result.shouldShowDiscernmentGate == true)
        #expect(result.discernmentMessage == "This may land as shame instead of correction.")
    }

    @Test("Answered prayer lifecycle wins over follow up")
    func answeredPrayerLifecycle() {
        let post = makePost(
            content: "God answered this prayer.",
            category: .prayer,
            prayerStatus: "answered",
            isAnsweredPrayer: true
        )
        let descriptor = service.lifecycleDescriptor(for: post)
        #expect(descriptor?.state == .answered)
    }

    @Test("Silent reaction summary stays qualitative")
    func silentReactionSummary() {
        let post = makePost(
            content: "Please pray for me.",
            category: .prayer,
            prayTapsCount: 2,
            encouragedCount: 1,
            savesCount: 1
        )
        let summary = service.silentReactionSummary(for: post, isAuthor: true)
        #expect(summary?.summaryText.contains("prayed with this") == true)
        #expect(summary?.summaryText.contains("encouraging") == true)
    }

    @Test("Thread summoning parser recognizes follow-up language")
    func threadSummoningQueryDetection() {
        #expect(service.parseThreadSummoningQuery("Show prayers I need to follow up on") == true)
        #expect(service.parseThreadSummoningQuery("more testimonies this week") == false)
    }
}
#endif
