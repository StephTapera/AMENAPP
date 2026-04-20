import Testing
import Foundation
@testable import AMENAPP

@Suite("Smart Share")
@MainActor
struct SmartShareTests {
    private let payloadFactory = SharePayloadFactory()
    private let rankingEngine = ShareRankingEngine()

    private func makePost(
        content: String = "Today’s verse spoke to me.",
        category: Post.PostCategory = .openTable,
        verseReference: String? = nil,
        churchNoteId: String? = nil
    ) -> Post {
        Post(
            id: UUID(),
            firebaseId: "post_123",
            authorId: "author_1",
            authorName: "Steph",
            authorUsername: "steph",
            authorInitials: "S",
            authorProfileImageURL: nil,
            timeAgo: "1m",
            content: content,
            category: category,
            topicTag: nil,
            visibility: .everyone,
            allowComments: true,
            commentPermissions: .everyone,
            imageURLs: nil,
            linkURL: nil,
            linkPreviewTitle: nil,
            linkPreviewDescription: nil,
            linkPreviewImageURL: nil,
            linkPreviewSiteName: nil,
            linkPreviewType: nil,
            verseReference: verseReference,
            verseText: nil,
            createdAt: Date(),
            amenCount: 0,
            lightbulbCount: 0,
            commentCount: 0,
            repostCount: 0,
            churchNoteId: churchNoteId
        )
    }

    @Test("Verse posts map to verse share content")
    func verseContentType() {
        let post = makePost(verseReference: "Philippians 4:13")
        #expect(payloadFactory.contentType(for: post) == .versePost)
    }

    @Test("Generated payload preserves attribution and AMEN deep link")
    func generatedPayloadIncludesAttribution() {
        let post = makePost()
        let payload = payloadFactory.makePayload(
            for: post,
            options: .default(for: .regularPost)
        )

        #expect(payload.text.contains("Steph"))
        #expect(payload.deepLink.absoluteString.contains("amen://post/"))
    }

    @Test("Prayer-circle targets rank above generic targets for prayer shares")
    func prayerRankingBoost() {
        let prayerTarget = SmartShareTarget(
            id: "1",
            type: .person,
            title: "Prayer Friend",
            subtitle: "@prayer",
            imageURL: nil,
            badge: "Prayer circle",
            score: 60,
            reasons: ["Prayer circle"],
            isOnline: false,
            conversation: nil,
            user: nil
        )
        let genericTarget = SmartShareTarget(
            id: "2",
            type: .person,
            title: "Friend",
            subtitle: "@friend",
            imageURL: nil,
            badge: "Likely to engage",
            score: 65,
            reasons: ["Likely to engage"],
            isOnline: false,
            conversation: nil,
            user: nil
        )

        let ranked = rankingEngine.rank(
            targets: [genericTarget, prayerTarget],
            filter: .suggested,
            query: "",
            contentType: .prayerRequest
        )

        #expect(ranked.first?.id == prayerTarget.id)
    }
}
