//
//  ProfilePictureUpdateHandler.swift
//  AMENAPP
//
//  Handles profile picture updates and propagates changes to user's posts
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

class ProfilePictureUpdateHandler {
    static let shared = ProfilePictureUpdateHandler()
    
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// Update user's profile picture and propagate to all their posts
    /// Call this when a user changes their profile picture
    func updateProfilePicture(newImageURL: String?) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ No authenticated user")
            throw NSError(domain: "ProfilePictureUpdate", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        print("🖼️ Updating profile picture for user: \(userId)")
        
        // 1. Update user document in Firestore
        let updateData: [String: Any] = [
            "profileImageURL": newImageURL ?? "",
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        try await db.collection("users").document(userId).updateData(updateData)
        print("✅ Updated user document with new profile image")
        
        // 2. Update UserDefaults cache
        UserProfileImageCache.shared.updateCachedProfileImage(url: newImageURL)
        print("✅ Updated cached profile image URL")
        
        // 3. Update all user's posts with new profile image URL (background task)
        Task.detached(priority: .utility) {
            do {
                try await PostProfileImageMigration.shared.migratePostsForUser(userId: userId)
                print("✅ Updated all posts with new profile image")
            } catch {
                print("⚠️ Failed to update posts with new profile image: \(error)")
                // Non-critical error - posts will be updated on next app launch
            }
        }
        
        // 4. Post notification for UI updates
        await MainActor.run {
            NotificationCenter.default.post(
                name: .profilePictureUpdated,
                object: nil,
                userInfo: ["userId": userId, "imageURL": newImageURL ?? ""]
            )
        }
        
        print("🎉 Profile picture update complete!")
    }
    
    /// Remove user's profile picture
    func removeProfilePicture() async throws {
        try await updateProfilePicture(newImageURL: nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let profilePictureUpdated = Notification.Name("profilePictureUpdated")
}
