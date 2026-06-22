// ChurchPostCardDraftService.swift
// AMENAPP
//
// Manages PostCard draft generation and publishing for church visits.
// Each ChurchPostCardType maps to a pre-filled template that the user
// can edit before publishing as a standard Post.

import Foundation
import FirebaseAuth

// MARK: - PostCardDraft

struct PostCardDraft: Identifiable {
    let id: String
    let type: ChurchPostCardType
    let churchId: String?
    let churchName: String
    var content: String
    let category: Post.PostCategory
    var isPublished: Bool

    init(
        type: ChurchPostCardType,
        churchId: String?,
        churchName: String
    ) {
        self.id = UUID().uuidString
        self.type = type
        self.churchId = churchId
        self.churchName = churchName
        self.content = type.templateContent(churchName: churchName)
        self.category = type.postCategory
        self.isPublished = false
    }
}

// MARK: - Template Content + Category Mapping

extension ChurchPostCardType {
    func templateContent(churchName: String) -> String {
        switch self {
        case .invite:
            return "I'm visiting \(churchName) this week and would love for you to join me! 🙏"
        case .recommend:
            return "I recently visited \(churchName) and wanted to share why it stood out to me…"
        case .gratitude:
            return "Grateful for \(churchName) and the community there. Here's what I appreciated…"
        case .testimony:
            return "God moved during my visit to \(churchName). Here's my testimony…"
        case .encouragement:
            return "If you're looking for a church home, consider visiting \(churchName)…"
        }
    }

    var postCategory: Post.PostCategory {
        switch self {
        case .invite, .recommend, .encouragement:
            return .openTable
        case .gratitude, .testimony:
            return .testimonies
        }
    }
}

// MARK: - ChurchPostCardDraftService

@MainActor
final class ChurchPostCardDraftService: ObservableObject {

    static let shared = ChurchPostCardDraftService()

    @Published var drafts: [PostCardDraft] = []

    private init() {}

    // MARK: - Generate Draft

    /// Creates a new PostCard draft for a church and returns it.
    @discardableResult
    func generateDraft(
        type: ChurchPostCardType,
        churchId: String?,
        churchName: String
    ) -> PostCardDraft {
        let draft = PostCardDraft(
            type: type,
            churchId: churchId,
            churchName: churchName
        )
        drafts.append(draft)

        // Link to church interaction
        if let churchId {
            ChurchInteractionService.shared.linkPostCardDraft(
                churchId: churchId,
                draftId: draft.id
            )
        }

        return draft
    }

    // MARK: - Publish Draft

    /// Publishes a draft as a real Post via PostsManager, then marks it published.
    func publishDraft(_ draft: PostCardDraft) {
        PostsManager.shared.createPost(
            content: draft.content,
            category: draft.category
        )

        // Mark as published locally
        if let idx = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[idx].isPublished = true
        }
    }

    // MARK: - Remove Draft

    func removeDraft(id: String) {
        drafts.removeAll { $0.id == id }
    }
}
