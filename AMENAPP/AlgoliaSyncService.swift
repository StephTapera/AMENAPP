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
        guard isSearchableUser(accountStatus: accountStatus, isDeactivated: isDeactivated) else {
            try? await deleteUser(userId: userId)
            return
        }

        _ = try await functions.httpsCallable("algolia_syncUser").call([
            "userId": userId,
            "displayName": userData["displayName"] as? String ?? "",
            "username": userData["username"] as? String ?? "",
            "usernameLowercase": userData["usernameLowercase"] as? String ?? "",
            "bio": userData["bio"] as? String ?? "",
            "followersCount": userData["followersCount"] as? Int ?? 0,
            "followingCount": userData["followingCount"] as? Int ?? 0,
            "profileImageURL": userData["profileImageURL"] as? String ?? "",
            "isVerified": userData["isVerified"] as? Bool ?? false,
            "createdAt": userData["createdAt"] as? Double ?? Date().timeIntervalSince1970,
            "accountStatus": accountStatus,
            "isDeactivated": isDeactivated
        ])
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

    // MARK: - Bulk Sync (Debug / Admin)

    func syncAllData() async throws {
        try await bulkSyncUsers()
        try await bulkSyncPosts()
    }

    func bulkSyncUsers() async throws {
        let snapshot = try await db.collection("users").getDocuments()
        for doc in snapshot.documents {
            try await syncUser(userId: doc.documentID, userData: doc.data())
        }
    }

    func bulkSyncPosts() async throws {
        let snapshot = try await db.collection("posts").getDocuments()
        for doc in snapshot.documents {
            try await syncPost(postId: doc.documentID, postData: doc.data())
        }
    }

    // MARK: - Helpers

    private func normalizedAccountStatus(from userData: [String: Any]) -> String {
        (userData["accountStatus"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "active"
    }

    private func isSearchableUser(accountStatus: String, isDeactivated: Bool) -> Bool {
        guard !isDeactivated else { return false }
        switch accountStatus {
        case "banned", "suspended", "deleted", "deactivated":
            return false
        default:
            return true
        }
    }
}
