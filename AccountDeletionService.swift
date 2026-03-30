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

@MainActor
final class AccountDeletionService: ObservableObject {
    static let shared = AccountDeletionService()
    private init() {}

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    // MARK: - Main Entry Point

    /// Full account deletion. Must be called after re-authentication.
    func deleteAccount(userId: String) async throws {
        dlog("🗑 [AccountDeletion] Starting deletion for \(userId)")

        // 1. Cancel any active Stripe subscriptions via Cloud Function
        try await cancelStripeSubscriptions(userId: userId)

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
            "users/\(userId)/blockedUsers"
        ]
        for path in subcollections {
            try await deleteCollectionBatch(path: path)
        }

        // 3. Delete user-authored content
        let contentCollections: [(collection: String, field: String)] = [
            ("posts",                   "userId"),
            ("prayerRequests",          "userId"),
            ("testimonies",             "userId"),
            ("churchNotes",             "userId"),
            ("mentorshipRelationships", "userId"),
            ("checkIns",                "userId"),
            ("follows",                 "followerId"),
            ("follows_index",           "followerId"),
            ("followRequests",          "requesterId"),
            ("savedPosts",              "userId"),
            ("drafts",                  "userId")
        ]
        for item in contentCollections {
            try await deleteDocumentsWhereField(
                collection: item.collection,
                field: item.field,
                equalTo: userId
            )
        }

        // 4. Mark conversations as deleted for this user (don't delete shared history)
        try await leaveAllConversations(userId: userId)

        // 5. Delete main user document
        try await db.document("users/\(userId)").delete()
        dlog("✅ [AccountDeletion] Firestore user doc deleted")

        // 6. Delete Firebase Storage files (profile photo + uploads)
        try await deleteStorageFiles(userId: userId)

        // 7. Delete Firebase Auth account — MUST be last
        try await Auth.auth().currentUser?.delete()
        dlog("✅ [AccountDeletion] Firebase Auth account deleted")

        // 8. Clear all local app state
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
        let snap = try await db.collection(collection)
            .whereField(field, isEqualTo: value)
            .limit(to: 200)
            .getDocuments()
        guard !snap.documents.isEmpty else { return }
        let batch = db.batch()
        snap.documents.forEach { batch.deleteDocument($0.reference) }
        try await batch.commit()
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

    private func deleteStorageFiles(userId: String) async throws {
        let storage = Storage.storage()
        let profileRef = storage.reference().child("users/\(userId)")
        do {
            let list = try await profileRef.listAll()
            for item in list.items {
                try? await item.delete()
            }
        } catch {
            dlog("⚠️ [AccountDeletion] Storage delete failed (non-fatal): \(error)")
        }
    }

    private func clearLocalState() {
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
        }
        // Clear keychain if needed (add SecItemDelete calls here)
    }
}
