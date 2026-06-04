// DiscussionThreadService.swift — AMEN App
// Wraps the 7 discussion Cloud Functions + Firestore listeners.
// All calls are @MainActor to avoid data races on Published state.

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class DiscussionThreadService {
    static let shared = DiscussionThreadService()
    private init() {}

    private let db        = Firestore.firestore()
    private let functions = Functions.functions()

    // MARK: - Thread (get or create)

    /// Returns the thread document for a post, creating one if it doesn't exist.
    /// Uses postId as the threadId (standard pattern for 1:1 post→thread).
    func getOrCreateThread(postId: String, postTitle: String?) async throws -> DiscussionThread {
        let ref = db.collection("threads").document(postId)
        let snap = try await ref.getDocument()

        if snap.exists, let thread = try? snap.data(as: DiscussionThread.self) {
            return thread
        }

        let now = Timestamp(date: Date())
        let authorUID = Auth.auth().currentUser?.uid
        let data: [String: Any] = [
            "postId":        postId,
            "postTitle":     postTitle as Any,
            "postType":      "general",
            "postAuthorUID": authorUID as Any,
            "isLocked":      false,
            "commentCount":  0,
            "createdAt":     now,
            "updatedAt":     now,
        ]
        try await ref.setData(data, merge: true)
        let created = try await ref.getDocument()
        return (try? created.data(as: DiscussionThread.self)) ?? DiscussionThread(
            postId: postId, postTitle: postTitle, postType: "general",
            postAuthorUID: authorUID,
            isLocked: false, commentCount: 0, bereanSummaryRef: nil,
            createdAt: now, updatedAt: now
        )
    }

    // MARK: - Real-time listeners

    func listenComments(
        threadId: String,
        onChange: @escaping ([DiscussionComment]) -> Void
    ) -> ListenerRegistration {
        db.collection("threads").document(threadId)
            .collection("comments")
            .whereField("isDeleted", isEqualTo: false)
            .whereField("destination", isEqualTo: "public")
            .order(by: "createdAt", descending: false)
            .limit(to: 100)
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    let comments = snap?.documents
                        .compactMap { try? $0.data(as: DiscussionComment.self) } ?? []
                    onChange(comments)
                }
            }
    }

    func listenThread(
        threadId: String,
        onChange: @escaping (DiscussionThread?) -> Void
    ) -> ListenerRegistration {
        db.collection("threads").document(threadId)
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    onChange(try? snap?.data(as: DiscussionThread.self))
                }
            }
    }

    func listenBereanSummary(
        path: String,
        onChange: @escaping (BereanThreadSummary?) -> Void
    ) -> ListenerRegistration {
        db.document(path)
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    onChange(try? snap?.data(as: BereanThreadSummary.self))
                }
            }
    }

    // MARK: - Cloud Function: askBerean

    func askBerean(threadId: String) async throws -> BereanThreadSummary {
        let callable = functions.httpsCallable("askBerean")
        let result   = try await callable.call(["threadId": threadId])
        guard let data = result.data as? [String: Any] else {
            throw DiscussionServiceError.unexpectedResponse
        }
        let now = Timestamp(date: Date())
        return BereanThreadSummary(
            id:               nil,
            summary:          data["summary"]        as? String ?? "",
            agreementPoints:  data["agreementPoints"] as? [String] ?? [],
            openQuestions:    data["openQuestions"]   as? [String] ?? [],
            biblicalRefs:     data["biblicalRefs"]    as? [String] ?? [],
            studyQuestions:   data["studyQuestions"]  as? [String] ?? [],
            isMock:           data["isMock"]          as? Bool    ?? false,
            tokenCount:       data["tokenCount"]      as? Int     ?? 0,
            createdAt:        now
        )
    }

    // MARK: - Cloud Function: detectDuplicate

    func detectDuplicate(
        threadId: String,
        draftBody: String
    ) async throws -> DiscussionDuplicateResult {
        let callable = functions.httpsCallable("detectDuplicate")
        let result   = try await callable.call(["threadId": threadId, "draftBody": draftBody])
        guard let data = result.data as? [String: Any] else { return .clean }
        let isDuplicate = data["isDuplicate"] as? Bool   ?? false
        let suggestion  = data["suggestion"]  as? String ?? ""
        if isDuplicate              { return .isDuplicate }
        if suggestion == "addAngle" { return .addAngle }
        return .clean
    }

    // MARK: - Cloud Function: postComment

    /// Returns the new commentId.
    func postComment(
        threadId: String,
        body: String,
        destination: DiscussionDestination = .public
    ) async throws -> String {
        let callable = functions.httpsCallable("postComment")
        let result   = try await callable.call([
            "threadId":    threadId,
            "body":        body,
            "destination": destination.rawValue
        ])
        guard let data = result.data as? [String: Any],
              let commentId = data["commentId"] as? String else {
            throw DiscussionServiceError.unexpectedResponse
        }
        return commentId
    }

    // MARK: - Cloud Function: markHelpful

    func markHelpful(threadId: String, commentId: String) async throws {
        let callable = functions.httpsCallable("markHelpful")
        _ = try await callable.call(["threadId": threadId, "commentId": commentId])
    }

    // MARK: - Cloud Function: computeReputation

    func fetchReputation() async throws -> DiscussionReputationTier {
        let callable = functions.httpsCallable("computeReputation")
        let result   = try await callable.call([:])
        guard let data = result.data as? [String: Any],
              let tierRaw = data["tier"] as? String else { return .none }
        return DiscussionReputationTier(rawValue: tierRaw) ?? .none
    }

    // MARK: - Errors

    enum DiscussionServiceError: LocalizedError {
        case unexpectedResponse

        var errorDescription: String? {
            switch self {
            case .unexpectedResponse:
                return "Unexpected response from server. Please try again."
            }
        }
    }
}
