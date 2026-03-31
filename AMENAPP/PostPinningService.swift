// PostPinningService.swift
// AMENAPP
//
// Threads-style single-post pinning for user profiles.
// Only one post can be pinned at a time per user.
// Does NOT modify any PostCard UI.
//
// Firestore path: users/{uid}/profile/pinned (document with pinnedPostId field)
// Separate from PinnedPostService — supports typed pin categories (testimony, teaching, etc.)

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - PinnedPostRecord Model

struct PinnedPostRecord: Codable {
    var postId: String
    var pinnedAt: Date
    var pinType: PinType

    enum PinType: String, Codable {
        case standard    // normal pin
        case testimony   // pinned as testimony
        case teaching    // pinned as teaching
        case churchNote  // pinned church note excerpt
    }
}

// MARK: - PostPinningService

@MainActor
final class PostPinningService: ObservableObject {

    static let shared = PostPinningService()

    @Published var pinnedPostId: String? = nil
    @Published var pinnedRecord: PinnedPostRecord? = nil

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Load

    /// Loads the current user's pinned post record from Firestore.
    func loadPinnedPost() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("PostPinningService: no authenticated user, skipping loadPinnedPost")
            return
        }

        do {
            let doc = try await db
                .collection("users")
                .document(uid)
                .collection("profile")
                .document("pinned")
                .getDocument()

            guard doc.exists, let data = doc.data() else {
                dlog("PostPinningService: no pinned record found for \(uid)")
                pinnedPostId = nil
                pinnedRecord = nil
                return
            }

            let postId = data["postId"] as? String ?? ""
            let pinnedAtTimestamp = data["pinnedAt"] as? Timestamp ?? Timestamp(date: .now)
            let pinTypeRaw = data["pinType"] as? String ?? PinnedPostRecord.PinType.standard.rawValue
            let pinType = PinnedPostRecord.PinType(rawValue: pinTypeRaw) ?? .standard

            let record = PinnedPostRecord(
                postId: postId,
                pinnedAt: pinnedAtTimestamp.dateValue(),
                pinType: pinType
            )
            pinnedRecord = record
            pinnedPostId = postId
            dlog("PostPinningService: loaded pinned post \(postId) (\(pinType.rawValue))")
        } catch {
            dlog("PostPinningService: loadPinnedPost error — \(error.localizedDescription)")
        }
    }

    // MARK: - Pin

    /// Pins a post to the user's profile.
    /// If another post is already pinned, it is unpinned first (one-pin-at-a-time rule).
    func pinPost(_ postId: String, type: PinnedPostRecord.PinType = .standard) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw PostPinningError.notAuthenticated
        }

        dlog("PostPinningService: pinning \(postId) as \(type.rawValue) for user \(uid)")

        // 1. Unpin existing pinned post if different
        if let currentId = pinnedPostId, currentId != postId {
            dlog("PostPinningService: unpinning existing post \(currentId) before pinning new one")
            try await unpinPost(currentId)
        }

        // 2. Build the new pinned record
        let pinnedRef = db
            .collection("users")
            .document(uid)
            .collection("profile")
            .document("pinned")

        let payload: [String: Any] = [
            "postId": postId,
            "pinnedAt": FieldValue.serverTimestamp(),
            "pinType": type.rawValue
        ]

        try await pinnedRef.setData(payload)

        // 3. Update published state
        let record = PinnedPostRecord(
            postId: postId,
            pinnedAt: Date(),
            pinType: type
        )
        pinnedRecord = record
        pinnedPostId = postId

        dlog("PostPinningService: pinned \(postId) successfully")
    }

    // MARK: - Unpin

    /// Unpins a post from the user's profile.
    func unpinPost(_ postId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw PostPinningError.notAuthenticated
        }

        dlog("PostPinningService: unpinning \(postId) for user \(uid)")

        let pinnedRef = db
            .collection("users")
            .document(uid)
            .collection("profile")
            .document("pinned")

        try await pinnedRef.delete()

        if pinnedPostId == postId {
            pinnedPostId = nil
            pinnedRecord = nil
        }

        dlog("PostPinningService: unpinned \(postId) successfully")
    }

    // MARK: - Query

    /// Returns true if the given postId is the currently pinned post.
    func isPinned(_ postId: String) -> Bool {
        pinnedPostId == postId
    }
}

// MARK: - Error Types

enum PostPinningError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to pin or unpin posts."
        }
    }
}
