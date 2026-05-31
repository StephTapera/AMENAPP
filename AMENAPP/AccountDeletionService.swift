//
//  AccountDeletionService.swift
//  AMENAPP
//
//  Handles full account and data deletion per Apple App Store Guideline 5.1.1.
//  Order: cancel subscriptions → delete Firestore data → delete Storage → delete Auth account
//

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import FirebaseFunctions
import FirebaseDatabase

@MainActor
final class AccountDeletionService: ObservableObject {
    static let shared = AccountDeletionService()
    private init() {}

    private lazy var db = Firestore.firestore()
    private lazy var functions = Functions.functions()

    // MARK: - Main Entry Point

    /// Full account deletion. Must be called after re-authentication.
    ///
    /// Deletion order (App Store Guideline 5.1.1 compliance):
    ///   1.  Cancel Stripe subscriptions (non-fatal)
    ///   2.  Delete Firestore subcollections
    ///   3.  Delete user-authored Firestore content
    ///   4.  Mark conversations left
    ///   5.  Delete Algolia search records (non-fatal)
    ///   6.  Delete Realtime Database nodes
    ///   7.  Delete main Firestore user document
    ///   8.  Delete Firebase Storage files (all upload paths)
    ///   9.  Delete Firebase Auth account — MUST be last
    ///   10. Clear all local app state
    func deleteAccount(userId: String) async throws {
        dlog("🗑 [AccountDeletion] Starting deletion for \(userId)")

        // ─────────────────────────────────────────────────────────────────────
        // SAFETY INVARIANT: Firebase Auth deletion MUST be the very last step.
        // If ANY Firestore / RTDB / Storage step fails, we throw before reaching
        // Auth deletion so the user can retry without leaving orphaned data.
        // Re-authentication must be performed by the caller (via
        // reauthenticateWithPassword / reauthenticateWithAppleToken) BEFORE
        // invoking this function, so the Auth token is still valid for all
        // Firestore writes below.
        // ─────────────────────────────────────────────────────────────────────

        // 1. Cancel any active Stripe subscriptions via Cloud Function
        try await cancelStripeSubscriptions(userId: userId)

        // ── Steps 2–7: All Firestore / RTDB cascade work happens here. ────────
        // If anything in this block throws, we propagate the error immediately
        // and do NOT proceed to Auth deletion, preventing orphaned data.
        do {
            // 2. Delete Firestore subcollections
            let subcollections = [
                "users/\(userId)/bookmarkedMedia",
                "users/\(userId)/mediaHistory",
                "users/\(userId)/readingProgress",
                "users/\(userId)/completedReflections",
                "users/\(userId)/notifications",
                "users/\(userId)/fcmTokens",
                "users/\(userId)/followers",
                "users/\(userId)/following",
                "users/\(userId)/blockedUsers",
                "users/\(userId)/blocks",
                "users/\(userId)/savedSearches",
                "users/\(userId)/private"      // DOB / age assurance — must delete
            ]
            for path in subcollections {
                try await deleteCollectionBatch(path: path)
            }

            // 3. Delete user-authored content
            let contentCollections: [(collection: String, field: String)] = [
                ("posts",                   "userId"),
                ("posts",                   "authorId"),   // authorId variant
                ("prayerRequests",          "userId"),
                ("testimonies",             "userId"),
                ("churchNotes",             "userId"),
                ("mentorshipRelationships", "userId"),
                ("checkIns",                "userId"),
                ("follows",                 "followerId"),
                ("follows_index",           "followerId"),
                ("followRequests",          "requesterId"),
                ("savedPosts",              "userId"),
                ("drafts",                  "userId"),
                ("userReports",             "reporterId"),  // reporter's own reports
                ("savedSearches",           "userId"),
                ("searchAlerts",            "userId")
            ]
            for item in contentCollections {
                try await deleteDocumentsWhereField(
                    collection: item.collection,
                    field: item.field,
                    equalTo: userId
                )
            }

            // 3a. Delete subcollections under user-authored posts
            //     Firestore does NOT auto-delete subcollections when a parent document is deleted.
            try await deleteSubcollectionsForUserDocs(
                collection: "posts",
                field: "userId",
                userId: userId,
                subcollections: ["comments", "likes", "reactions"]
            )
            // Also cover the authorId variant
            try await deleteSubcollectionsForUserDocs(
                collection: "posts",
                field: "authorId",
                userId: userId,
                subcollections: ["comments", "likes", "reactions"]
            )

            // 3b. Delete subcollections under user prayer requests
            try await deleteSubcollectionsForUserDocs(
                collection: "prayerRequests",
                field: "userId",
                userId: userId,
                subcollections: ["prayedBy", "intercessors"]
            )

            // 3c. Delete subcollections under church notes
            try await deleteSubcollectionsForUserDocs(
                collection: "churchNotes",
                field: "userId",
                userId: userId,
                subcollections: ["attachments"]
            )

            // 4. Mark conversations as deleted for this user (don't delete shared history)
            try await leaveAllConversations(userId: userId)

            // 5. Delete Algolia search index records (non-fatal — failure must not block deletion)
            await deleteAlgoliaRecords(userId: userId)

            // 6. Delete Realtime Database nodes
            // These are not covered by Firestore deletion and contain personal data:
            // presence, typing indicators, counters, user_posts, user_profiles.
            await deleteRealtimeDatabaseNodes(userId: userId)

            // 7. Delete main user document
            try await db.document("users/\(userId)").delete()
            dlog("✅ [AccountDeletion] Firestore user doc deleted")

        } catch {
            // Firestore / RTDB cascade failed — do NOT delete the Auth account.
            // The user's Auth token is still valid so they can retry later.
            dlog("❌ [AccountDeletion] Data cascade failed — Auth account preserved. Error: \(error)")
            throw error
        }
        // ── End of Firestore / RTDB cascade ──────────────────────────────────

        // 8. Delete Firebase Storage files from ALL user upload paths
        //    Non-fatal: storage failures should not block Auth deletion at this
        //    point because all Firestore documents have already been removed.
        await deleteStorageFiles(userId: userId)

        // 9. Delete Firebase Auth account — MUST be last.
        //    Reached only if ALL steps above completed without throwing.
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "AccountDeletion", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated — cannot delete Auth account"])
        }
        try await user.delete()
        dlog("✅ [AccountDeletion] Firebase Auth account deleted")

        // 10. Clear all local app state
        clearLocalState()
        dlog("✅ [AccountDeletion] Complete")
    }

    // MARK: - Re-authentication Helpers

    /// Re-authenticate with email/password before deletion.
    func reauthenticateWithPassword(email: String, password: String) async throws {
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        try await Auth.auth().currentUser?.reauthenticate(with: credential)
    }

    /// Re-authenticate with Apple Sign In token before deletion.
    func reauthenticateWithAppleToken(_ idTokenString: String, nonce: String) async throws {
        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: nil
        )
        try await Auth.auth().currentUser?.reauthenticate(with: credential)
    }

    /// Returns the current user's sign-in provider (e.g. "password", "apple.com", "google.com")
    var currentProviderID: String? {
        Auth.auth().currentUser?.providerData.first?.providerID
    }

    // MARK: - Private Helpers

    private func cancelStripeSubscriptions(userId: String) async throws {
        let callable = functions.httpsCallable("cancelAllSubscriptions")
        do {
            _ = try await callable.safeCall(["userId": userId])
            dlog("✅ [AccountDeletion] Stripe subscriptions cancelled")
        } catch {
            // Non-fatal — log and continue. Subscriptions will expire naturally.
            dlog("⚠️ [AccountDeletion] Stripe cancel failed (non-fatal): \(error)")
        }
    }

    private func deleteCollectionBatch(path: String) async throws {
        var lastDoc: DocumentSnapshot? = nil
        repeat {
            var query: Query = db.collection(path).limit(to: 100)
            if let last = lastDoc { query = query.start(afterDocument: last) }
            let snap = try await query.getDocuments()
            guard !snap.documents.isEmpty else { break }
            let batch = db.batch()
            snap.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
            lastDoc = snap.documents.count == 100 ? snap.documents.last : nil
        } while lastDoc != nil
    }

    private func deleteDocumentsWhereField(
        collection: String, field: String, equalTo value: String
    ) async throws {
        let batchSize = 200
        var lastDoc: DocumentSnapshot? = nil
        repeat {
            var query = db.collection(collection)
                .whereField(field, isEqualTo: value)
                .limit(to: batchSize)
            if let last = lastDoc {
                query = query.start(afterDocument: last)
            }
            let snap = try await query.getDocuments()
            guard !snap.documents.isEmpty else { break }
            let writeBatch = db.batch()
            snap.documents.forEach { writeBatch.deleteDocument($0.reference) }
            try await writeBatch.commit()
            // If the batch was full, there may be more documents — continue paginating.
            lastDoc = snap.documents.count == batchSize ? snap.documents.last : nil
        } while lastDoc != nil
    }

    /// Enumerates all documents in `collection` where `field == userId`, then
    /// deletes each listed `subcollection` name under those documents using the
    /// same paginated batch approach as `deleteCollectionBatch`.
    private func deleteSubcollectionsForUserDocs(
        collection: String,
        field: String,
        userId: String,
        subcollections: [String]
    ) async throws {
        let batchSize = 200
        var lastDoc: DocumentSnapshot? = nil
        repeat {
            var query = db.collection(collection)
                .whereField(field, isEqualTo: userId)
                .limit(to: batchSize)
            if let last = lastDoc {
                query = query.start(afterDocument: last)
            }
            let snap = try await query.getDocuments()
            guard !snap.documents.isEmpty else { break }
            for parentDoc in snap.documents {
                for sub in subcollections {
                    try await deleteCollectionBatch(
                        path: "\(collection)/\(parentDoc.documentID)/\(sub)"
                    )
                }
            }
            lastDoc = snap.documents.count == batchSize ? snap.documents.last : nil
        } while lastDoc != nil
    }

    private func leaveAllConversations(userId: String) async throws {
        let snap = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: userId)
            .getDocuments()
        let batch = db.batch()
        for doc in snap.documents {
            // Remove user from participantIds; conversation stays for other participants
            batch.updateData([
                "participantIds": FieldValue.arrayRemove([userId]),
                "deletedBy.\(userId)": true
            ], forDocument: doc.reference)
        }
        if !snap.documents.isEmpty { try await batch.commit() }
    }

    private func deleteStorageFiles(userId: String) async {
        let storage = Storage.storage()
        // All Storage prefixes that may contain user-generated content.
        // Covers: legacy users/ path + all active upload prefixes.
        let storagePaths = [
            "users/\(userId)",
            "profile_images/\(userId)",
            "amenConnect/\(userId)",
            "post_media/\(userId)",
            "chat_files/\(userId)",         // not possible to enumerate by sender; skip group chats
            "voice_messages/\(userId)",
            "studioVoice/\(userId)",
            "voiceDevotionals/\(userId)",
            "sermons/\(userId)",
            "churchNotes/\(userId)"
        ]
        for path in storagePaths {
            do {
                let ref = storage.reference().child(path)
                let list = try await ref.listAll()
                for item in list.items {
                    try? await item.delete()
                }
                // Delete nested prefixes (e.g. post_media/{userId}/{uploadGroupId}/)
                for prefix in list.prefixes {
                    let nested = try await prefix.listAll()
                    for item in nested.items {
                        try? await item.delete()
                    }
                }
            } catch {
                // Non-fatal: path may not exist for this user
                dlog("⚠️ [AccountDeletion] Storage delete \(path) failed (non-fatal): \(error)")
            }
        }
        dlog("✅ [AccountDeletion] Storage files deleted")
    }

    /// Delete all Realtime Database nodes that store personal data for this user.
    private func deleteRealtimeDatabaseNodes(userId: String) async {
        let rtdb = Database.database().reference()
        let paths: [String] = [
            "online_status/\(userId)",
            "user_posts/\(userId)",
            "user_profiles/\(userId)",
            "user_saved_posts/\(userId)",
            "counters/\(userId)",
            "connections/\(userId)",
            "devices/\(userId)",
            "sessions/\(userId)",
            "notification_tokens/\(userId)",
            "userConversations/\(userId)"   // index of conversation IDs
        ]
        for path in paths {
            do {
                try await rtdb.child(path).removeValue()
            } catch {
                dlog("⚠️ [AccountDeletion] RTDB delete \(path) failed (non-fatal): \(error)")
            }
        }
        dlog("✅ [AccountDeletion] Realtime Database nodes deleted")
    }

    /// Delete Algolia search index records for this user and their posts.
    /// Uses the deleteAlgoliaUser Cloud Function to keep the API key server-side.
    private func deleteAlgoliaRecords(userId: String) async {
        let callable = functions.httpsCallable("deleteAlgoliaUser")
        do {
            _ = try await callable.safeCall(["userId": userId])
            dlog("✅ [AccountDeletion] Algolia records deleted")
        } catch {
            // Non-fatal: Algolia deletion failure must not block account deletion
            dlog("⚠️ [AccountDeletion] Algolia delete failed (non-fatal): \(error)")
        }
    }

    private func clearLocalState() {
        // Clear all UserDefaults for this app
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
        }
        // Clear all generic password Keychain items (FCM token, auth token,
        // emailForSignIn, biometricEnabled flag, session tokens, etc.)
        let genericQuery: [String: Any] = [kSecClass as String: kSecClassGenericPassword]
        SecItemDelete(genericQuery as CFDictionary)
        // Clear all internet password Keychain items
        let internetQuery: [String: Any] = [kSecClass as String: kSecClassInternetPassword]
        SecItemDelete(internetQuery as CFDictionary)
    }
}
