// AmenSpaceDiscussionService.swift — AMEN App
// Space-scoped discussion threads: listen and create threads partitioned
// by SpaceDiscussionChannelType (questions | prayer | wins | general).
// Firestore layout: threads/{threadId} with spaceId + channelType fields.

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class AmenSpaceDiscussionService {
    static let shared = AmenSpaceDiscussionService()
    private init() {}

    private let db = Firestore.firestore()

    // MARK: - Listen

    func listenThreads(
        spaceId: String,
        channelType: SpaceDiscussionChannelType?,
        onChange: @escaping ([DiscussionThread]) -> Void
    ) -> ListenerRegistration {
        let base = db.collection("threads")
            .whereField("spaceId", isEqualTo: spaceId)
            .order(by: "updatedAt", descending: true)
            .limit(to: 50)

        let query: Query = channelType.map { ch in
            db.collection("threads")
                .whereField("spaceId", isEqualTo: spaceId)
                .whereField("channelType", isEqualTo: ch.rawValue)
                .order(by: "updatedAt", descending: true)
                .limit(to: 50)
        } ?? base

        return query.addSnapshotListener { snap, error in
            if let error {
                print("[AmenSpaceDiscussionService] listenThreads error: \(error)")
                return
            }
            Task { @MainActor in
                let threads = snap?.documents
                    .compactMap { try? $0.data(as: DiscussionThread.self) } ?? []
                onChange(threads)
            }
        }
    }

    // MARK: - CF-typed fetch (used by SpaceDiscussionsViewModel.loadCF)

    func getDiscussions(spaceId: String) async throws -> [CFDiscussionThread] {
        let snap = try await db.collection("threads")
            .whereField("spaceId", isEqualTo: spaceId)
            .order(by: "updatedAt", descending: true)
            .limit(to: 50)
            .getDocuments()
        return snap.documents.compactMap { doc -> CFDiscussionThread? in
            guard let thread = try? doc.data(as: DiscussionThread.self) else { return nil }
            return CFDiscussionThread(
                id:              thread.postId,
                title:           thread.postTitle ?? "Untitled Thread",
                authorFirstName: "",
                category:        channelToCategory(thread.channelType),
                replyCount:      thread.commentCount,
                isPinned:        false,
                isAIGenerated:   false,
                lastActivityAt:  thread.updatedAt.dateValue()
            )
        }
    }

    // MARK: - CF-typed create (used by NewSpaceThreadComposerSheet)

    func createDiscussion(
        spaceId: String,
        title: String,
        body: String,
        category: DiscussionCategory
    ) async throws -> CFDiscussionThread {
        let uid = Auth.auth().currentUser?.uid
        let suffix = String(UUID().uuidString.prefix(8))
        let channel = categoryToChannel(category)
        let threadId = "space_\(spaceId)_\(category.rawValue)_\(suffix)"
        let now = Timestamp(date: Date())
        let ref = db.collection("threads").document(threadId)
        let data: [String: Any] = [
            "postId":        threadId,
            "postTitle":     title,
            "postType":      "discussion",
            "postAuthorUID": uid as Any,
            "spaceId":       spaceId,
            "channelType":   channel.rawValue,
            "body":          body,
            "isLocked":      false,
            "commentCount":  0,
            "createdAt":     now,
            "updatedAt":     now,
        ]
        try await ref.setData(data)
        return CFDiscussionThread(
            id:              threadId,
            title:           title,
            authorFirstName: "",
            category:        category,
            replyCount:      0,
            isPinned:        false,
            isAIGenerated:   false,
            lastActivityAt:  Date()
        )
    }

    // MARK: - Channel ↔ Category helpers

    private func channelToCategory(_ rawValue: String?) -> DiscussionCategory {
        switch SpaceDiscussionChannelType(rawValue: rawValue ?? "general") ?? .general {
        case .prayer:    return .prayer
        case .questions: return .question
        case .wins, .general: return .general
        }
    }

    private func categoryToChannel(_ category: DiscussionCategory) -> SpaceDiscussionChannelType {
        switch category {
        case .prayer:                         return .prayer
        case .question:                       return .questions
        case .study, .general, .announcement: return .general
        }
    }

    // MARK: - Create (SpaceDiscussionChannelType-typed, used by legacy NewSpaceThreadSheet)

    func createThread(
        spaceId: String,
        title: String,
        channelType: SpaceDiscussionChannelType
    ) async throws -> DiscussionThread {
        let uid = Auth.auth().currentUser?.uid
        let suffix = String(UUID().uuidString.prefix(8))
        let threadId = "space_\(spaceId)_\(channelType.rawValue)_\(suffix)"
        let now = Timestamp(date: Date())
        let ref = db.collection("threads").document(threadId)
        let data: [String: Any] = [
            "postId":        threadId,
            "postTitle":     title,
            "postType":      "discussion",
            "postAuthorUID": uid as Any,
            "spaceId":       spaceId,
            "channelType":   channelType.rawValue,
            "isLocked":      false,
            "commentCount":  0,
            "createdAt":     now,
            "updatedAt":     now,
        ]
        try await ref.setData(data)
        return DiscussionThread(
            postId:           threadId,
            postTitle:        title,
            postType:         "discussion",
            postAuthorUID:    uid,
            transcriptRef:    nil,
            isLocked:         false,
            lockedReason:     nil,
            commentCount:     0,
            bereanSummaryRef: nil,
            spaceId:          spaceId,
            channelType:      channelType.rawValue,
            createdAt:        now,
            updatedAt:        now
        )
    }
}
