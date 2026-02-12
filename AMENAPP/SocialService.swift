//
//  SocialService.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//

import Foundation
import UIKit
import FirebaseFirestore
import FirebaseAuth
import Combine

/// Service for managing social interactions (follow/unfollow, profile pictures, etc.)
@MainActor
class SocialService: ObservableObject {
    static let shared = SocialService()
    
    @Published var followers: [UserModel] = []
    @Published var following: [UserModel] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let firebaseManager = FirebaseManager.shared
    private let userService = UserService()
    
    private init() {}
    
    // MARK: - Follow/Unfollow Actions
    
    // ⚠️ DEPRECATED: Use FollowService.shared instead
    // These methods have been moved to FollowService to avoid duplicate follow logic
    
    // MARK: - Mute Accounts
    
    /// Mute a user for a specified duration
    func muteUser(_ userId: String, duration: TimeInterval) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "SocialService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let muteUntil = Date().addingTimeInterval(duration)
        
        try await Firestore.firestore()
            .collection("users")
            .document(currentUserId)
            .updateData([
                "mutedUsers.\(userId)": Timestamp(date: muteUntil)
            ])
        
        print("🔇 Muted user \(userId) until \(muteUntil)")
    }
    
    /// Unmute a user
    func unmuteUser(_ userId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "SocialService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        try await Firestore.firestore()
            .collection("users")
            .document(currentUserId)
            .updateData([
                "mutedUsers.\(userId)": FieldValue.delete()
            ])
        
        print("🔊 Unmuted user \(userId)")
    }
    
    /// Check if a user is muted
    func isUserMuted(_ userId: String, mutedUsers: [String: Timestamp]) -> Bool {
        guard let muteTimestamp = mutedUsers[userId] else {
            return false
        }
        
        let muteUntil = muteTimestamp.dateValue()
        return Date() < muteUntil
    }
    
    // MARK: - Fetch Followers/Following
    
    /// Fetch list of users who follow the specified user
    func fetchFollowers(for userId: String) async throws -> [UserModel] {
        isLoading = true
        defer { isLoading = false }
        
        print("👥 Fetching followers for user: \(userId)")
        
        let db = Firestore.firestore()
        
        // Get all follow relationships where this user is being followed
        let followsSnapshot = try await db.collection("follows")
            .whereField("followingId", isEqualTo: userId)
            .getDocuments()
        
        let followerIds = followsSnapshot.documents.compactMap { doc -> String? in
            try? doc.data(as: FollowRelationship.self).followerId
        }
        
        print("   Found \(followerIds.count) followers")
        
        // Fetch user profiles for all followers
        var followers: [UserModel] = []
        for followerId in followerIds {
            do {
                let user = try await firebaseManager.fetchDocument(
                    from: "users/\(followerId)",
                    as: UserModel.self
                )
                followers.append(user)
            } catch {
                print("⚠️ Failed to fetch follower profile: \(followerId)")
            }
        }
        
        self.followers = followers
        return followers
    }
    
    /// Fetch list of users that the specified user follows
    func fetchFollowing(for userId: String) async throws -> [UserModel] {
        isLoading = true
        defer { isLoading = false }
        
        print("👥 Fetching following for user: \(userId)")
        
        let db = Firestore.firestore()
        
        // Get all follow relationships where this user is the follower
        let followsSnapshot = try await db.collection("follows")
            .whereField("followerId", isEqualTo: userId)
            .getDocuments()
        
        let followingIds = followsSnapshot.documents.compactMap { doc -> String? in
            try? doc.data(as: FollowRelationship.self).followingId
        }
        
        print("   User is following \(followingIds.count) people")
        
        // Fetch user profiles for all following
        var following: [UserModel] = []
        for followingId in followingIds {
            do {
                let user = try await firebaseManager.fetchDocument(
                    from: "users/\(followingId)",
                    as: UserModel.self
                )
                following.append(user)
            } catch {
                print("⚠️ Failed to fetch following profile: \(followingId)")
            }
        }
        
        self.following = following
        return following
    }
    
    // MARK: - Mutual Followers
    
    /// Fetch users who both follow and are followed by the specified user
    func fetchMutualFollows(for userId: String) async throws -> [UserModel] {
        let followers = try await fetchFollowers(for: userId)
        let following = try await fetchFollowing(for: userId)
        
        let followerIds = Set(followers.map { $0.id ?? "" })
        let followingIds = Set(following.map { $0.id ?? "" })
        
        let mutualIds = followerIds.intersection(followingIds)
        
        return followers.filter { mutualIds.contains($0.id ?? "") }
    }
    
    // MARK: - Profile Picture Management
    
    /// Upload a profile picture
    func uploadProfilePicture(_ image: UIImage) async throws -> String {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw SocialServiceError.notAuthenticated
        }
        
        isLoading = true
        defer { isLoading = false }
        
        print("📸 Uploading profile picture...")
        
        // Upload to Firebase Storage
        let path = "profile_images/\(currentUserId)/profile_\(Date().timeIntervalSince1970).jpg"
        let downloadURL = try await firebaseManager.uploadImage(image, to: path, compressionQuality: 0.8)
        
        print("✅ Profile picture uploaded: \(downloadURL.absoluteString)")
        
        // Update user profile with new image URL
        try await firebaseManager.updateDocument(
            ["profileImageURL": downloadURL.absoluteString, "updatedAt": Date()],
            at: "users/\(currentUserId)"
        )
        
        return downloadURL.absoluteString
    }
    
    /// Delete current profile picture
    func deleteProfilePicture() async throws {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw SocialServiceError.notAuthenticated
        }
        
        isLoading = true
        defer { isLoading = false }
        
        print("📸 Deleting profile picture...")
        
        // Get current profile image URL
        let user = try await firebaseManager.fetchDocument(
            from: "users/\(currentUserId)",
            as: UserModel.self
        )
        
        // Delete from Storage if exists
        if let imageURL = user.profileImageURL,
           let path = extractStoragePath(from: imageURL) {
            try? await firebaseManager.deleteFile(at: path)
        }
        
        // Remove from user profile
        try await firebaseManager.updateDocument(
            ["profileImageURL": FieldValue.delete(), "updatedAt": Date()],
            at: "users/\(currentUserId)"
        )
        
        print("✅ Profile picture deleted")
    }
    
    /// Upload additional photos (for dating profiles, gallery, etc.)
    func uploadPhoto(_ image: UIImage, albumName: String = "gallery") async throws -> String {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw SocialServiceError.notAuthenticated
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let timestamp = Date().timeIntervalSince1970
        let path = "user_photos/\(currentUserId)/\(albumName)/photo_\(timestamp).jpg"
        let downloadURL = try await firebaseManager.uploadImage(image, to: path, compressionQuality: 0.85)
        
        return downloadURL.absoluteString
    }
    
    // MARK: - Helper Methods
    
    private func extractStoragePath(from url: String) -> String? {
        // Extract storage path from Firebase Storage URL
        // Format: https://firebasestorage.googleapis.com/.../o/path%2Fto%2Ffile.jpg?...
        guard let encodedPath = url.components(separatedBy: "/o/").last?.components(separatedBy: "?").first else {
            return nil
        }
        return encodedPath.removingPercentEncoding
    }
}

// MARK: - Errors

enum SocialServiceError: LocalizedError {
    case notAuthenticated
    case cannotFollowSelf
    case relationshipNotFound
    case uploadFailed
    case invalidImage
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to perform this action"
        case .cannotFollowSelf:
            return "You cannot follow yourself"
        case .relationshipNotFound:
            return "Follow relationship not found"
        case .uploadFailed:
            return "Failed to upload image"
        case .invalidImage:
            return "Invalid image format"
        }
    }
}
