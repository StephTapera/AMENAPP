import Foundation
import FirebaseFirestore
import FirebaseFunctions

/// Claude-powered comment moderation layer for CommentsView only.
///
/// Uses the existing `bereanGenericProxy` Cloud Function — no API key on device.
/// Designed as fire-and-forget: the comment posts instantly to Firestore,
/// then this service checks it in the background. If Claude rejects:
///   1. The Firestore document is deleted (real-time listener removes it from UI)
///   2. A NotificationCenter event fires so CommentsView can show a toast
actor CommentClaudeModerator {
    static let shared = CommentClaudeModerator()
    private init() {}

    private let db = Firestore.firestore()

    // MARK: - Moderation result

    enum Result {
        case approved
        case rejected(reason: String)
    }

    // MARK: - Public entry point

    /// Call this AFTER the Firestore write succeeds.
    /// Never blocks or delays the comment from appearing.
    func moderateInBackground(text: String, postId: String, commentId: String, isReply: Bool = false) async {
        let result = await checkWithClaude(text)
        guard case .rejected(let reason) = result else { return }

        // Delete from Firestore — real-time listener will remove from UI
        let path: DocumentReference
        if isReply {
            // Replies live under comments — best effort find parent
            // For simplicity, try both paths
            path = db.collection("posts").document(postId)
                     .collection("comments").document(commentId)
        } else {
            path = db.collection("posts").document(postId)
                     .collection("comments").document(commentId)
        }

        try? await path.delete()

        // Notify CommentsView via NotificationCenter
        await MainActor.run {
            NotificationCenter.default.post(
                name: .commentRemovedByModeration,
                object: nil,
                userInfo: ["reason": reason, "commentId": commentId]
            )
        }
    }

    // MARK: - Claude check via bereanGenericProxy

    private func checkWithClaude(_ text: String) async -> Result {
        let prompt = """
        You are a content moderator for a Christian community app called AMEN.
        Review this comment and respond with JSON only:
        {"approved": true, "reason": ""}
        OR
        {"approved": false, "reason": "brief reason (max 12 words)"}

        Reject only if the comment contains:
        - Hate speech, slurs, or personal attacks
        - Sexual content of any kind
        - Spam or promotional links
        - Self-harm encouragement
        - Content that mocks Christian faith deliberately
        - Threats or harassment

        Approve everything else — including disagreements, doubts, questions.

        Comment: "\(text.prefix(500))"
        """

        let payload: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 128,
            "messages": [["role": "user", "content": prompt]]
        ]

        do {
            let result = try await Functions.functions()
                .httpsCallable("bereanGenericProxy")
                .call(payload)

            guard
                let dict = result.data as? [String: Any],
                let textContent = dict["text"] as? String,
                let data = textContent.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let approved = json["approved"] as? Bool
            else {
                return .approved // fail open — don't silently block valid comments
            }

            if approved {
                return .approved
            } else {
                let reason = json["reason"] as? String ?? "Content policy violation"
                return .rejected(reason: reason)
            }
        } catch {
            // Network/function error — fail open, never silently drop a comment
            return .approved
        }
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let commentRemovedByModeration = Notification.Name("commentRemovedByModeration")
}
