//
//  AlgoliaSyncService.swift
//  AMENAPP
//
//  Created by Steph on 1/28/26.
//
//  All Algolia index WRITES are server-side only (Cloud Functions).
//  This service calls Firebase callables — it never holds an Algolia write key.
//

import Foundation
import FirebaseFunctions
import FirebaseFirestore

// MARK: - Algolia Record Models

struct AlgoliaUserRecord: Codable {
    let objectID: String
    let displayName: String
    let username: String
    let usernameLowercase: String
    let bio: String
    let followersCount: Int
    let followingCount: Int
    let profileImageURL: String
    let isVerified: Bool
    let createdAt: Double
    let accountStatus: String
    let isDeactivated: Bool
    let isSearchable: Bool
    let _tags: [String]
}

struct AlgoliaPostRecord: Codable {
    let objectID: String
    let content: String
    let authorId: String
    let authorName: String
    let category: String
    let amenCount: Int
    let commentCount: Int
    let shareCount: Int
    let createdAt: Double
    let isPublic: Bool
    let _tags: [String]
}

/// Syncs Firestore data to Algolia via server-side Cloud Functions.
/// The iOS client holds only a search (read-only) key. All index writes
/// go through `algolia_syncUser`, `algolia_syncPost`, `algolia_deleteUser`,
/// and `algolia_deletePost` callables that run with the admin API key in
/// Secret Manager.
@MainActor
class AlgoliaSyncService {
    static let shared = AlgoliaSyncService()

    private let functions = Functions.functions()
    private lazy var db = Firestore.firestore()

    private init() {}

    // MARK: - Sync Users

    func syncUser(userId: String, userData: [String: Any]) async throws {
        let accountStatus = normalizedAccountStatus(from: userData)
        let isDeactivated = userData["isDeactivated"] as? Bool ?? false
        // PRIVACY FIX 2026-05-28: private accounts must not be indexed in Algolia
        let isPrivate = userData["isPrivate"] as? Bool ?? false
        guard isSearchableUser(accountStatus: accountStatus, isDeactivated: isDeactivated, isPrivate: isPrivate) else {
            // Remove from index if previously indexed (e.g. user just switched to private mode)
            try? await deleteUser(userId: userId)
            return
        }

        // SECURITY (H-03): only sync follower/following counts if the user's privacy
        // settings allow them to be publicly visible. Algolia is a public search index
        // readable by all signed-in users; exposing counts here bypasses the
        // showFollowerCount / showFollowingCount toggles on the profile screen.
        let showFollowerCount = userData["showFollowerCount"] as? Bool ?? true
        let showFollowingCount = userData["showFollowingCount"] as? Bool ?? true

        var payload: [String: Any] = [
            "userId": userId,
            "displayName": userData["displayName"] as? String ?? "",
            "username": userData["username"] as? String ?? "",
            "usernameLowercase": userData["usernameLowercase"] as? String ?? "",
            "bio": userData["bio"] as? String ?? "",
            "profileImageURL": userData["profileImageURL"] as? String ?? "",
            "isVerified": userData["isVerified"] as? Bool ?? false,
            "createdAt": userData["createdAt"] as? Double ?? Date().timeIntervalSince1970,
            "accountStatus": accountStatus,
            "isDeactivated": isDeactivated
        ]
        if showFollowerCount {
            payload["followersCount"] = userData["followersCount"] as? Int ?? 0
        }
        if showFollowingCount {
            payload["followingCount"] = userData["followingCount"] as? Int ?? 0
        }

        _ = try await functions.httpsCallable("algolia_syncUser").call(payload)
        dlog("✅ AlgoliaSyncService: syncUser \(userId) dispatched to Cloud Function")
    }

    func syncPost(postId: String, postData: [String: Any]) async throws {
        let category = postData["category"] as? String ?? "general"
        _ = try await functions.httpsCallable("algolia_syncPost").call([
            "postId": postId,
            "content": postData["content"] as? String ?? "",
            "authorId": postData["authorId"] as? String ?? "",
            "authorName": postData["authorName"] as? String ?? "",
            "category": category,
            "amenCount": postData["amenCount"] as? Int ?? 0,
            "commentCount": postData["commentCount"] as? Int ?? 0,
            "shareCount": postData["shareCount"] as? Int ?? 0,
            "createdAt": postData["createdAt"] as? Double ?? Date().timeIntervalSince1970,
            "isPublic": postData["isPublic"] as? Bool ?? true
        ])
        dlog("✅ AlgoliaSyncService: syncPost \(postId) dispatched to Cloud Function")
    }

    // MARK: - Delete from Algolia

    func deleteUser(userId: String) async throws {
        _ = try await functions.httpsCallable("algolia_deleteUser").call(["userId": userId])
        dlog("✅ AlgoliaSyncService: deleteUser \(userId) dispatched to Cloud Function")
    }

    func deletePost(postId: String) async throws {
        _ = try await functions.httpsCallable("algolia_deletePost").call(["postId": postId])
        dlog("✅ AlgoliaSyncService: deletePost \(postId) dispatched to Cloud Function")
    }

    // MARK: - Org Sync

    /// Syncs a single org stub to the Algolia `organizations` index via the
    /// server-side `algolia_syncOrg` Cloud Function.
    /// The function is admin-gated on the server; calling it from a non-admin
    /// account is a no-op (the CF returns permission-denied silently).
    func syncOrg(orgId: String) async {
        let fn = Functions.functions().httpsCallable("algolia_syncOrg")
        try? await fn.call(["orgId": orgId])
        dlog("✅ AlgoliaSyncService: syncOrg \(orgId) dispatched to Cloud Function")
    }

    // MARK: - Bulk Sync (Debug / Admin only)
    // IMPORTANT: These methods are for admin tooling and debug builds only.
    // They must never be called during normal user sessions — each page fetches
    // up to 100 documents to avoid unbounded full-collection reads on large databases.
    // For production re-indexing, trigger the server-side Cloud Function instead.

    func syncAllData() async throws {
        try await bulkSyncUsers()
        try await bulkSyncPosts()
    }

    func bulkSyncUsers() async throws {
        let snapshot = try await db.collection("users").limit(to: 100).getDocuments()
        for doc in snapshot.documents {
            try await syncUser(userId: doc.documentID, userData: doc.data())
        }
        dlog("⚠️ AlgoliaSyncService.bulkSyncUsers: limited to first 100 users. Use server-side CF for full re-index.")
    }

    func bulkSyncPosts() async throws {
        let snapshot = try await db.collection("posts").limit(to: 100).getDocuments()
        for doc in snapshot.documents {
            try await syncPost(postId: doc.documentID, postData: doc.data())
        }
        dlog("⚠️ AlgoliaSyncService.bulkSyncPosts: limited to first 100 posts. Use server-side CF for full re-index.")
    }

    // MARK: - Helpers

    private func normalizedAccountStatus(from userData: [String: Any]) -> String {
        (userData["accountStatus"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "active"
    }

    // PRIVACY FIX 2026-05-28: private accounts must not appear in discovery search.
    // isPrivate = true means the account is opt-out of public discovery — their
    // profile should only be visible to approved followers, not searchable by everyone.
    private func isSearchableUser(accountStatus: String, isDeactivated: Bool, isPrivate: Bool = false) -> Bool {
        guard !isDeactivated, !isPrivate else { return false }
        switch accountStatus {
        case "banned", "suspended", "deleted", "deactivated":
            return false
        default:
            return true
        }
    }
}
