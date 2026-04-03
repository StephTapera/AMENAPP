//
//  SmartEngagementSignalService.swift
//  AMENAPP
//
//  Records and retrieves smart (non-vanity) engagement signals for posts.
//
//  Design rules:
//  - Raw engagement counts (encouragedCount, savedToNotesCount, etc.) are NEVER
//    surfaced publicly. They exist only in Firestore for internal scoring.
//  - The only public output is `fetchPublicLabels(for:)`, which returns qualitative
//    labels computed server-side (e.g. "Many saved this", "Being discussed").
//  - `computeDiscussionHealth(postId:)` returns a normalised 0.0–1.0 score for
//    feed ranking purposes — it is not displayed directly to users.
//  - Each signal action is idempotent per (userId, postId) pair to prevent
//    duplicate increments from retry logic.
//

import Foundation
// import FirebaseFirestore   ← add when Firebase SDK is linked
// import FirebaseAuth        ← add when Firebase SDK is linked
// import FirebaseFunctions   ← add for server-computed health score

// MARK: - Supporting Types

// SmartEngagementSignals is defined in AMENAccountTypeSystem.swift

// MARK: - Service

/// Records and retrieves smart (non-vanity) engagement signals for posts.
///
/// Firestore collection: `postEngagementSignals`
/// Document ID: `postId`
///
/// Signal actions increment server-side counters via Firestore transactions.
/// Public-facing surfaces receive only qualitative labels — never raw integers.
@MainActor
final class SmartEngagementSignalService: ObservableObject {

    // Firestore reference placeholder:
    // private let db = Firestore.firestore()
    // private let functions = Functions.functions()

    // MARK: - Signal Recording

    /// Records an encourage action for a post.
    ///
    /// Increments `encouragedCount` in `postEngagementSignals/{postId}`.
    /// The operation is idempotent — a (userId, postId) pair can only be counted once.
    ///
    /// Raw counts are never surfaced publicly.
    ///
    /// - Parameters:
    ///   - postId: The ID of the post being encouraged.
    ///   - userId: The UID of the user performing the action.
    /// - Throws: A Firestore error if the transaction fails.
    func recordEncourage(postId: String, userId: String) async throws {
        // Idempotency guard — check whether this user has already encouraged this post:
        // let idempotencyDoc = db.collection("postEngagementActions")
        //     .document("\(postId)_\(userId)_encourage")
        //
        // Firestore transaction:
        // try await db.runTransaction { transaction, _ in
        //     let existing = try? transaction.getDocument(idempotencyDoc)
        //     guard existing?.exists != true else { return nil }
        //     let signalRef = self.db.collection("postEngagementSignals").document(postId)
        //     transaction.updateData(["encouragedCount": FieldValue.increment(Int64(1))], forDocument: signalRef)
        //     transaction.setData(["recordedAt": FieldValue.serverTimestamp()], forDocument: idempotencyDoc)
        //     return nil
        // }
    }

    /// Records a save-to-notes action for a post.
    ///
    /// Increments `savedToNotesCount` in `postEngagementSignals/{postId}`.
    ///
    /// - Parameters:
    ///   - postId: The ID of the post being saved.
    ///   - userId: The UID of the user performing the action.
    /// - Throws: A Firestore error if the write fails.
    func recordSaveToNotes(postId: String, userId: String) async throws {
        // Firestore increment:
        // try await db.collection("postEngagementSignals").document(postId)
        //     .setData(["savedToNotesCount": FieldValue.increment(Int64(1))], merge: true)
    }

    /// Records a prayerful response to a post.
    ///
    /// Increments `prayerfulResponseCount` in `postEngagementSignals/{postId}`.
    ///
    /// - Parameters:
    ///   - postId: The ID of the post receiving the prayerful response.
    ///   - userId: The UID of the user responding.
    /// - Throws: A Firestore error if the write fails.
    func recordPrayerfulResponse(postId: String, userId: String) async throws {
        // Firestore increment:
        // try await db.collection("postEngagementSignals").document(postId)
        //     .setData(["prayerfulResponseCount": FieldValue.increment(Int64(1))], merge: true)
    }

    /// Records a share action for a post.
    ///
    /// Increments `sharedCount` in `postEngagementSignals/{postId}`.
    ///
    /// - Parameters:
    ///   - postId: The ID of the post being shared.
    ///   - userId: The UID of the user sharing.
    /// - Throws: A Firestore error if the write fails.
    func recordShare(postId: String, userId: String) async throws {
        // Firestore increment:
        // try await db.collection("postEngagementSignals").document(postId)
        //     .setData(["sharedCount": FieldValue.increment(Int64(1))], merge: true)
    }

    // MARK: - Public Labels

    /// Fetches the public-safe qualitative labels for a post's engagement signals.
    ///
    /// These labels are computed server-side (via a Cloud Function or Firestore extension)
    /// and stored in `postEngagementSignals/{postId}.publicLabels`.
    ///
    /// Examples: `"Many saved this"`, `"Being discussed"`, `"People are praying over this"`.
    /// Raw counts are never included in the returned array.
    ///
    /// - Parameter postId: The post to fetch labels for.
    /// - Returns: An array of human-readable labels. Returns `[]` if no signals exist yet.
    /// - Throws: A Firestore error if the fetch fails.
    func fetchPublicLabels(for postId: String) async throws -> [String] {
        // Firestore fetch:
        // let doc = try await db.collection("postEngagementSignals").document(postId).getDocument()
        // guard let data = doc.data() else { return [] }
        // let signals = try Firestore.Decoder().decode(SmartEngagementSignals.self, from: data)
        // return signals.publicLabels  // NEVER return raw counts

        return []
    }

    // MARK: - Discussion Health

    /// Computes a discussion health score (0.0–1.0) for a post.
    ///
    /// The score factors in reply diversity (range of distinct voices),
    /// avoidance of reword-only replies, and ratio of prayerful/encourage
    /// signals to total interactions.
    ///
    /// Used internally for feed ranking. Not shown directly to users.
    ///
    /// - Parameter postId: The post to score.
    /// - Returns: A normalised health score between `0.0` (low health) and `1.0` (high health).
    /// - Throws: A Firestore or Functions error if the computation fails.
    func computeDiscussionHealth(postId: String) async throws -> Double {
        // Option A — server-computed via Cloud Function:
        // let result = try await functions.httpsCallable("computeDiscussionHealth")
        //     .call(["postId": postId])
        // return (result.data as? [String: Any])?["score"] as? Double ?? 0.0

        // Option B — locally estimated from reply metadata in Firestore:
        // let snapshot = try await db.collection("replies")
        //     .whereField("postId", isEqualTo: postId)
        //     .getDocuments()
        // ... compute diversity score from snapshot ...

        return 0.0
    }
}

// MARK: - Errors

enum SmartEngagementError: LocalizedError {
    case signalNotFound
    case duplicateAction
    case healthComputationFailed

    var errorDescription: String? {
        switch self {
        case .signalNotFound:
            return "No engagement signals found for this post."
        case .duplicateAction:
            return "This engagement action has already been recorded."
        case .healthComputationFailed:
            return "Could not compute discussion health score."
        }
    }
}
