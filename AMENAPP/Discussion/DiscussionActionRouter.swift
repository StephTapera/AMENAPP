// DiscussionActionRouter.swift — AMEN App
import Foundation
import FirebaseRemoteConfig
import FirebaseFirestore
import UIKit

enum DiscussionAction: String, CaseIterable, Sendable {
    case markHelpful, share, shareToSpaces, report, reply, copyText, pin, delete

    var label: String {
        switch self {
        case .markHelpful:   return "Mark Helpful"
        case .share:         return "Share"
        case .shareToSpaces: return "Share to Spaces"
        case .report:        return "Report"
        case .reply:         return "Reply"
        case .copyText:      return "Copy Text"
        case .pin:           return "Pin"
        case .delete:        return "Delete"
        }
    }

    var icon: String {
        switch self {
        case .markHelpful:   return "hand.thumbsup"
        case .share:         return "square.and.arrow.up"
        case .shareToSpaces: return "person.3"
        case .report:        return "exclamationmark.triangle"
        case .reply:         return "arrowshape.turn.up.left"
        case .copyText:      return "doc.on.doc"
        case .pin:           return "pin"
        case .delete:        return "trash"
        }
    }

    var isDestructive: Bool { self == .delete || self == .report }
}

@MainActor
final class DiscussionActionRouter {
    static let shared = DiscussionActionRouter()
    private init() {}

    private var isEnabled: Bool {
        RemoteConfig.remoteConfig().configValue(forKey: "discussion_actions_enabled").boolValue
    }

    func availableActions(isOwnComment: Bool, isElder: Bool) -> [DiscussionAction] {
        guard isEnabled else { return [.markHelpful, .share] }
        var actions: [DiscussionAction] = [.markHelpful, .reply, .share, .copyText]
        if isElder        { actions.append(.pin) }
        if isOwnComment   { actions.append(.delete) }
        else              { actions.append(.report) }
        return actions
    }

    /// Executes the given action against the comment. Returns true on success.
    func perform(_ action: DiscussionAction, comment: DiscussionComment, threadTitle: String?) async throws -> Bool {
        guard let commentId = comment.id else { return false }
        let db = Firestore.firestore()
        let commentRef = db.collection("threads").document(comment.threadId)
            .collection("comments").document(commentId)

        switch action {
        case .markHelpful:
            try await commentRef.updateData(["helpfulCount": FieldValue.increment(Int64(1))])
            return true

        case .copyText:
            await MainActor.run {
                UIPasteboard.general.string = comment.body
            }
            return true

        case .share:
            let shareText = comment.body
            await MainActor.run {
                UIPasteboard.general.string = shareText
            }
            return true

        case .pin:
            try await commentRef.updateData(["isPinned": true])
            return true

        case .delete:
            try await commentRef.updateData(["isDeleted": true])
            return true

        case .report:
            try await db.collection("contentReports").addDocument(data: [
                "threadId": comment.threadId,
                "commentId": commentId,
                "authorUID": comment.authorUID,
                "reason": "user_report",
                "createdAt": FieldValue.serverTimestamp()
            ])
            return true

        case .reply, .shareToSpaces:
            return true
        }
    }
}
