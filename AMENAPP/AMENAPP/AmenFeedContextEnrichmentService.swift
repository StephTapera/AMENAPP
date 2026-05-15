import Foundation
import FirebaseAuth
import FirebaseFunctions

// Calls `attachFeedContextToRankedPosts` after the feed is loaded and applies the returned
// contextsByPostId map to posts that do not already have a Firestore-decoded feedContext.
// This is fire-and-forget safe — failures are silent and the feed displays without labels.
@MainActor
final class AmenFeedContextEnrichmentService {
    static let shared = AmenFeedContextEnrichmentService()

    private let functions = Functions.functions()
    private let isoFormatter = ISO8601DateFormatter()

    private init() {}

    func enrich(_ posts: inout [Post]) async {
        guard Auth.auth().currentUser != nil, !posts.isEmpty else { return }

        let payloads = posts.compactMap { makePayload(for: $0) }
        guard !payloads.isEmpty else { return }

        let callData: [String: Any] = [
            "posts": payloads,
            "followingIds": [String](),
            "sessionCardsServed": 0,
            "sessionCap": 25,
            "interests": [
                "engagedTopics": [String: Int](),
                "engagedAuthors": [String: Int](),
                "preferredCategories": [String: Int](),
                "onboardingGoals": [String]()
            ]
        ]

        do {
            let result = try await functions
                .httpsCallable("attachFeedContextToRankedPosts")
                .call(callData)
            guard let data = result.data as? [String: Any],
                  let contextsByPostId = data["contextsByPostId"] as? [String: [String: Any]] else { return }

            for i in posts.indices where posts[i].feedContext == nil {
                let postId = posts[i].firebaseId ?? posts[i].id.uuidString
                if let raw = contextsByPostId[postId] {
                    posts[i].feedContext = decodeContext(raw)
                }
            }
        } catch {
            AmenFeedContextAnalyticsTracker.shared.trackDebug("context_enrichment_failed", metadata: [
                "reason": error.localizedDescription
            ])
        }
    }

    private func makePayload(for post: Post) -> [String: Any]? {
        let id = post.firebaseId ?? post.id.uuidString
        guard !id.isEmpty else { return nil }
        var payload: [String: Any] = [
            "id": id,
            "authorId": post.authorId,
            "content": post.content,
            "category": post.category.rawValue,
            "amenCount": post.amenCount,
            "commentCount": post.commentCount,
            "createdAt": post.createdAt.timeIntervalSince1970,
            "lowTrustAuthor": post.lowTrustAuthor,
            "flaggedForReview": post.flaggedForReview,
            "removed": post.removed
        ]
        if let topicTag = post.topicTag { payload["topicTag"] = topicTag }
        if let churchId = post.sharedChurchId { payload["churchId"] = churchId }
        if let prayerId = post.linkedPrayerRequestId { payload["linkedPrayerRequestId"] = prayerId }
        return payload
    }

    private func decodeContext(_ raw: [String: Any]) -> AmenFeedContextLabel? {
        guard let contextId = raw["contextId"] as? String,
              let contextType = raw["contextType"] as? String,
              let type = AmenFeedContextType(rawValue: contextType),
              let rawTitle = raw["contextTitle"] as? String else { return nil }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let destTypeRaw = raw["contextDestinationType"] as? String ?? ""
        let destType = AmenFeedContextDestinationType(rawValue: destTypeRaw) ?? type.defaultDestination
        let destId = raw["contextDestinationId"] as? String
        let expiresAt: Date? = (raw["contextExpiresAt"] as? String).flatMap { isoFormatter.date(from: $0) }

        return AmenFeedContextLabel(
            id: contextId,
            type: type,
            title: title,
            reason: raw["contextReason"] as? String ?? type.fallbackCopy,
            confidence: raw["contextConfidence"] as? Double ?? 0,
            priority: raw["contextPriority"] as? Int ?? type.priorityWeight,
            destination: AmenFeedContextDestination(type: destType, id: destId),
            topicId: raw["contextTopicId"] as? String,
            verseRef: raw["contextVerseRef"] as? String,
            churchId: raw["contextChurchId"] as? String,
            communityId: raw["contextCommunityId"] as? String,
            expiresAt: expiresAt,
            isSensitive: raw["contextIsSensitive"] as? Bool ?? false,
            isDismissible: raw["contextIsDismissible"] as? Bool ?? true,
            analyticsId: raw["contextAnalyticsId"] as? String ?? contextId
        )
    }
}
