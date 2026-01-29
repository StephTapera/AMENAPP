//
//  AlgoliaSyncService.swift
//  AMENAPP
//
//  Created by Steph on 1/28/26.
//
//  Service for syncing Firestore data to Algolia search indexes
//

import Foundation
import FirebaseFirestore
import Search

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

/// Service responsible for syncing Firestore data to Algolia for instant search
@MainActor
class AlgoliaSyncService {
    static let shared = AlgoliaSyncService()
    
    // MARK: - Properties
    
    private var writeClient: SearchClient?
    private let usersIndexName = "users"
    private let postsIndexName = "posts"
    private let db = Firestore.firestore()
    
    // MARK: - Initialization
    
    private init() {
        setupWriteClient()
    }
    
    private func setupWriteClient() {
        let appID = AlgoliaConfig.applicationID
        let writeKey = AlgoliaConfig.writeAPIKey
        
        // Validate credentials
        guard !appID.isEmpty && appID != "YOUR_APP_ID",
              !writeKey.isEmpty && writeKey != "YOUR_WRITE_API_KEY" else {
            print("⚠️ Algolia Write API Key not configured - syncing disabled")
            print("   Update AlgoliaConfig.writeAPIKey to enable sync")
            return
        }
        
        // Initialize write client with write/admin key
        do {
            writeClient = try SearchClient(appID: appID, apiKey: writeKey)
            print("✅ Algolia sync service initialized")
            print("   App ID: \(appID.prefix(8))...")
            print("   Ready to sync data to Algolia")
        } catch {
            print("❌ Failed to initialize Algolia write client: \(error)")
        }
    }
    
    // MARK: - Sync Users
    
    /// Sync a single user to Algolia
    /// Call this when a user is created or updated
    func syncUser(userId: String, userData: [String: Any]) async throws {
        guard let client = writeClient else {
            print("⚠️ Algolia sync disabled - skipping user sync")
            return
        }
        
        print("🔄 Syncing user \(userId) to Algolia...")
        
        // Prepare user data for Algolia
        let algoliaRecord = AlgoliaUserRecord(
            objectID: userId,
            displayName: userData["displayName"] as? String ?? "",
            username: userData["username"] as? String ?? "",
            usernameLowercase: userData["usernameLowercase"] as? String ?? "",
            bio: userData["bio"] as? String ?? "",
            followersCount: userData["followersCount"] as? Int ?? 0,
            followingCount: userData["followingCount"] as? Int ?? 0,
            profileImageURL: userData["profileImageURL"] as? String ?? "",
            isVerified: userData["isVerified"] as? Bool ?? false,
            createdAt: userData["createdAt"] as? Double ?? Date().timeIntervalSince1970,
            _tags: ["user"]
        )
        
        do {
            // Save to Algolia index using saveObject
            let response = try await client.saveObject(
                indexName: usersIndexName,
                body: algoliaRecord
            )
            
            print("✅ User \(userId) synced to Algolia (task: \(response.taskID))")
        } catch {
            print("❌ Failed to sync user to Algolia: \(error)")
            throw error
        }
    }
    
    /// Sync a single post to Algolia
    /// Call this when a post is created or updated
    func syncPost(postId: String, postData: [String: Any]) async throws {
        guard let client = writeClient else {
            print("⚠️ Algolia sync disabled - skipping post sync")
            return
        }
        
        print("🔄 Syncing post \(postId) to Algolia...")
        
        // Prepare post data for Algolia
        let category = postData["category"] as? String ?? "general"
        let algoliaRecord = AlgoliaPostRecord(
            objectID: postId,
            content: postData["content"] as? String ?? "",
            authorId: postData["authorId"] as? String ?? "",
            authorName: postData["authorName"] as? String ?? "",
            category: category,
            amenCount: postData["amenCount"] as? Int ?? 0,
            commentCount: postData["commentCount"] as? Int ?? 0,
            shareCount: postData["shareCount"] as? Int ?? 0,
            createdAt: postData["createdAt"] as? Double ?? Date().timeIntervalSince1970,
            isPublic: postData["isPublic"] as? Bool ?? true,
            _tags: ["post", category]
        )
        
        do {
            // Save to Algolia index using saveObject
            let response = try await client.saveObject(
                indexName: postsIndexName,
                body: algoliaRecord
            )
            
            print("✅ Post \(postId) synced to Algolia (task: \(response.taskID))")
        } catch {
            print("❌ Failed to sync post to Algolia: \(error)")
            throw error
        }
    }
    
    // MARK: - Delete from Algolia
    
    /// Delete a user from Algolia index
    /// Call this when a user is deleted or account is deactivated
    func deleteUser(userId: String) async throws {
        guard let client = writeClient else {
            print("⚠️ Algolia sync disabled - skipping user deletion")
            return
        }
        
        print("🗑️ Deleting user \(userId) from Algolia...")
        
        do {
            let response = try await client.deleteObject(
                indexName: usersIndexName,
                objectID: userId
            )
            print("✅ User \(userId) deleted from Algolia (task: \(response.taskID))")
        } catch {
            print("❌ Failed to delete user from Algolia: \(error)")
            throw error
        }
    }
    
    /// Delete a post from Algolia index
    /// Call this when a post is deleted
    func deletePost(postId: String) async throws {
        guard let client = writeClient else {
            print("⚠️ Algolia sync disabled - skipping post deletion")
            return
        }
        
        print("🗑️ Deleting post \(postId) from Algolia...")
        
        do {
            let response = try await client.deleteObject(
                indexName: postsIndexName,
                objectID: postId
            )
            print("✅ Post \(postId) deleted from Algolia (task: \(response.taskID))")
        } catch {
            print("❌ Failed to delete post from Algolia: \(error)")
            throw error
        }
    }
    
    // MARK: - Bulk Sync (Initial Setup)
    
    /// Bulk sync all existing users from Firestore to Algolia
    /// Run this once to populate Algolia with existing data
    func bulkSyncUsers(limit: Int = 1000) async throws {
        guard let client = writeClient else {
            throw NSError(
                domain: "AlgoliaSyncService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Algolia not configured"]
            )
        }
        
        print("🔄 Starting bulk user sync (limit: \(limit))...")
        
        // Fetch users from Firestore
        let snapshot = try await db.collection("users")
            .limit(to: limit)
            .getDocuments()
        
        print("📥 Fetched \(snapshot.documents.count) users from Firestore")
        
        var records: [AlgoliaUserRecord] = []
        
        for document in snapshot.documents {
            let data = document.data()
            let record = AlgoliaUserRecord(
                objectID: document.documentID,
                displayName: data["displayName"] as? String ?? "",
                username: data["username"] as? String ?? "",
                usernameLowercase: data["usernameLowercase"] as? String ?? "",
                bio: data["bio"] as? String ?? "",
                followersCount: data["followersCount"] as? Int ?? 0,
                followingCount: data["followingCount"] as? Int ?? 0,
                profileImageURL: data["profileImageURL"] as? String ?? "",
                isVerified: data["isVerified"] as? Bool ?? false,
                createdAt: data["createdAt"] as? Double ?? Date().timeIntervalSince1970,
                _tags: ["user"]
            )
            records.append(record)
        }
        
        // Batch save to Algolia
        if !records.isEmpty {
            let responses = try await client.saveObjects(
                indexName: usersIndexName,
                objects: records
            )
            let taskIDs = responses.map { String($0.taskID) }.joined(separator: ", ")
            print("✅ Bulk synced \(records.count) users to Algolia (tasks: \(taskIDs))")
        } else {
            print("⚠️ No users to sync")
        }
    }
    
    /// Bulk sync all existing posts from Firestore to Algolia
    /// Run this once to populate Algolia with existing data
    func bulkSyncPosts(limit: Int = 1000) async throws {
        guard let client = writeClient else {
            throw NSError(
                domain: "AlgoliaSyncService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Algolia not configured"]
            )
        }
        
        print("🔄 Starting bulk post sync (limit: \(limit))...")
        
        // Fetch posts from Firestore
        let snapshot = try await db.collection("posts")
            .limit(to: limit)
            .getDocuments()
        
        print("📥 Fetched \(snapshot.documents.count) posts from Firestore")
        
        var records: [AlgoliaPostRecord] = []
        
        for document in snapshot.documents {
            let data = document.data()
            let category = data["category"] as? String ?? "general"
            let record = AlgoliaPostRecord(
                objectID: document.documentID,
                content: data["content"] as? String ?? "",
                authorId: data["authorId"] as? String ?? "",
                authorName: data["authorName"] as? String ?? "",
                category: category,
                amenCount: data["amenCount"] as? Int ?? 0,
                commentCount: data["commentCount"] as? Int ?? 0,
                shareCount: data["shareCount"] as? Int ?? 0,
                createdAt: data["createdAt"] as? Double ?? Date().timeIntervalSince1970,
                isPublic: data["isPublic"] as? Bool ?? true,
                _tags: ["post", category]
            )
            records.append(record)
        }
        
        // Batch save to Algolia
        if !records.isEmpty {
            let responses = try await client.saveObjects(
                indexName: postsIndexName,
                objects: records
            )
            let taskIDs = responses.map { String($0.taskID) }.joined(separator: ", ")
            print("✅ Bulk synced \(records.count) posts to Algolia (tasks: \(taskIDs))")
        } else {
            print("⚠️ No posts to sync")
        }
    }
    
    /// Sync all data (users + posts) to Algolia
    /// Use this for initial setup to populate Algolia with existing Firestore data
    func syncAllData() async throws {
        print("🚀 Starting full data sync to Algolia...")
        
        // Sync users
        do {
            try await bulkSyncUsers()
        } catch {
            print("❌ User sync failed: \(error)")
        }
        
        // Sync posts
        do {
            try await bulkSyncPosts()
        } catch {
            print("❌ Post sync failed: \(error)")
        }
        
        print("✅ Full data sync complete!")
    }
}

// MARK: - Usage Examples

/*
 📝 HOW TO USE THIS SERVICE:
 
 1️⃣ INITIAL SETUP (one time):
 ─────────────────────────────
 // Sync all existing Firestore data to Algolia
 Task {
     do {
         try await AlgoliaSyncService.shared.syncAllData()
         print("All data synced to Algolia!")
     } catch {
         print("Sync failed: \(error)")
     }
 }
 
 
 2️⃣ SYNC WHEN CREATING/UPDATING USER:
 ─────────────────────────────────────
 // In your user creation/update code
 func updateUserProfile(userId: String, displayName: String, bio: String) async throws {
     // 1. Update Firestore
     let userData: [String: Any] = [
         "displayName": displayName,
         "bio": bio,
         "username": "johndoe",
         "followersCount": 100
     ]
     
     try await db.collection("users").document(userId).setData(userData)
     
     // 2. Sync to Algolia
     try await AlgoliaSyncService.shared.syncUser(userId: userId, userData: userData)
 }
 
 
 3️⃣ SYNC WHEN CREATING/UPDATING POST:
 ────────────────────────────────────
 // In your post creation code
 func createPost(content: String, category: String) async throws {
     let postId = UUID().uuidString
     
     // 1. Save to Firestore
     let postData: [String: Any] = [
         "content": content,
         "authorName": "John Doe",
         "category": category,
         "amenCount": 0,
         "commentCount": 0,
         "createdAt": Date().timeIntervalSince1970
     ]
     
     try await db.collection("posts").document(postId).setData(postData)
     
     // 2. Sync to Algolia
     try await AlgoliaSyncService.shared.syncPost(postId: postId, postData: postData)
 }
 
 
 4️⃣ DELETE FROM ALGOLIA:
 ───────────────────────
 // When deleting a user
 func deleteUser(userId: String) async throws {
     // 1. Delete from Firestore
     try await db.collection("users").document(userId).delete()
     
     // 2. Delete from Algolia
     try await AlgoliaSyncService.shared.deleteUser(userId: userId)
 }
 
 
 5️⃣ SEARCH WITH ALGOLIA:
 ───────────────────────
 // Use AlgoliaSearchService to search
 let users = try await AlgoliaSearchService.shared.searchUsers(query: "john")
 let posts = try await AlgoliaSearchService.shared.searchPosts(query: "faith")
 
 
 ⚠️ IMPORTANT NOTES:
 ──────────────────
 - Run syncAllData() ONCE to populate Algolia with existing data
 - After that, sync individual records on create/update/delete
 - Algolia is eventually consistent (updates may take 1-2 seconds)
 - The Write API Key should be kept secure in production
 - Consider using Firebase Functions for production sync
 */
