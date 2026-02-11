//
//  PostProfileImageMigration.swift
//  AMENAPP
//
//  Migration utility to add profile image URLs to existing posts
//

import Foundation
import FirebaseFirestore

class PostProfileImageMigration {
    static let shared = PostProfileImageMigration()
    
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// Check if migration is needed
    func checkStatus() async throws -> (totalPosts: Int, needsMigration: Int) {
        print("🔍 Checking post profile image migration status...")
        
        let snapshot = try await db.collection("posts").getDocuments()
        let totalPosts = snapshot.documents.count
        
        let needsMigration = snapshot.documents.filter { doc in
            let data = doc.data()
            let hasProfileImage = data["authorProfileImageURL"] as? String
            return hasProfileImage == nil || hasProfileImage?.isEmpty == true
        }.count
        
        print("📊 Migration Status:")
        print("   Total posts: \(totalPosts)")
        print("   Need migration: \(needsMigration)")
        
        return (totalPosts, needsMigration)
    }
    
    /// Migrate all posts to include author profile image URLs
    /// This fetches the author's profile image URL from their user document and adds it to their posts
    func migrateAllPosts() async throws {
        print("🔧 Starting post profile image migration...")
        
        let postsSnapshot = try await db.collection("posts").getDocuments()
        var migratedCount = 0
        var errorCount = 0
        
        for postDoc in postsSnapshot.documents {
            do {
                let postData = postDoc.data()
                
                // Skip if already has profile image URL
                if let existingURL = postData["authorProfileImageURL"] as? String, !existingURL.isEmpty {
                    continue
                }
                
                guard let authorId = postData["authorId"] as? String else {
                    print("⚠️ Post \(postDoc.documentID) missing authorId")
                    errorCount += 1
                    continue
                }
                
                // Fetch author's profile image URL
                let userDoc = try await db.collection("users").document(authorId).getDocument()
                
                guard let userData = userDoc.data() else {
                    print("⚠️ User not found for authorId: \(authorId)")
                    errorCount += 1
                    continue
                }
                
                let profileImageURL = userData["profileImageURL"] as? String ?? ""
                
                // Update post with profile image URL
                try await db.collection("posts").document(postDoc.documentID).updateData([
                    "authorProfileImageURL": profileImageURL
                ])
                
                migratedCount += 1
                
                if migratedCount % 10 == 0 {
                    print("✅ Migrated \(migratedCount) posts so far...")
                }
                
            } catch {
                print("❌ Error migrating post \(postDoc.documentID): \(error)")
                errorCount += 1
            }
        }
        
        print("✅ Migration complete!")
        print("   Migrated: \(migratedCount)")
        print("   Errors: \(errorCount)")
    }
    
    /// Migrate posts for a specific user (useful when a user updates their profile picture)
    func migratePostsForUser(userId: String) async throws {
        print("🔧 Migrating posts for user: \(userId)")
        
        // Get user's profile image URL
        let userDoc = try await db.collection("users").document(userId).getDocument()
        
        guard let userData = userDoc.data() else {
            print("❌ User not found: \(userId)")
            throw FirebaseError.documentNotFound
        }
        
        let profileImageURL = userData["profileImageURL"] as? String ?? ""
        
        // Get all posts by this user
        let postsSnapshot = try await db.collection("posts")
            .whereField("authorId", isEqualTo: userId)
            .getDocuments()
        
        print("📊 Found \(postsSnapshot.documents.count) posts for user")
        
        // Update each post with the profile image URL
        for postDoc in postsSnapshot.documents {
            try await db.collection("posts").document(postDoc.documentID).updateData([
                "authorProfileImageURL": profileImageURL
            ])
        }
        
        print("✅ Updated \(postsSnapshot.documents.count) posts with profile image URL")
    }
}

// MARK: - Firebase Error (if not already defined elsewhere)

enum FirebaseError: LocalizedError {
    case documentNotFound
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .documentNotFound:
            return "Document not found"
        case .unauthorized:
            return "Unauthorized access"
        }
    }
}
