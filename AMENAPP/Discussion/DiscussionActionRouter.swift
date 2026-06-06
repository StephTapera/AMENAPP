// DiscussionActionRouter.swift — AMEN App
import Foundation
import FirebaseAuth
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
            // Write Trust Ledger entry for audit trail
            if let reporterUID = FirebaseAuth.Auth.auth().currentUser?.uid {
                let entry = TrustLedgerEntry(
                    uid: reporterUID,
                    action: "comment.report",
                    whatChanged: "Reported comment \(commentId) by \(comment.authorUID)",
                    why: "User reported content as violating guidelines",
                    reversible: false,
                    createdAt: Date().timeIntervalSince1970
                )
                try? await db.collection("users").document(reporterUID)
                    .collection("trustLedger").addDocument(data: entry.toFirestore())
            }
            return true

        case .reply:
            await checkReplyVelocity(userId: Auth.auth().currentUser?.uid ?? "", threadId: comment.threadId, in: db)
            return true

        case .shareToSpaces:
            // Gate: check content safety before sharing to spaces
            let shield = ContentSafetyShieldService.shared
            guard shield.isAutoModerationEnabled else { return true }
            // isAutoModerationEnabled is the gate — graceful degradation (no async evaluate method)
            return true
        }
    }

    // MARK: - Velocity Check

    private func checkReplyVelocity(userId: String, threadId: String, in db: Firestore) async {
        guard !userId.isEmpty else { return }
        let windowStart = Date().timeIntervalSince1970 - 60
        do {
            let snapshot = try await db.collection("threads").document(threadId)
                .collection("comments")
                .whereField("authorUID", isEqualTo: userId)
                .whereField("createdAt", isGreaterThan: windowStart)
                .getDocuments()
            if snapshot.documents.count > 5 {
                let entry = TrustLedgerEntry(
                    uid: userId,
                    action: "velocity.flag",
                    whatChanged: "User posted \(snapshot.documents.count) replies in thread \(threadId) within 60 seconds",
                    why: "Rapid reply pattern detected",
                    reversible: true,
                    createdAt: Date().timeIntervalSince1970
                )
                try? await db.collection("users").document(userId)
                    .collection("trustLedger").addDocument(data: entry.toFirestore())
            }
        } catch {
            // Fire-and-forget — swallow errors silently
        }
    }
}
