//
//  UserProfileImageCache.swift
//  AMENAPP
//
//  Utility to cache and manage user profile image URLs
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

class UserProfileImageCache {
    static let shared = UserProfileImageCache()
    
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// Cache the current user's profile data in UserDefaults for fast access
    func cacheCurrentUserProfile() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ No authenticated user to cache profile")
            return
        }
        
        do {
            let userDoc = try await db.collection("users").document(userId).getDocument()
            
            guard let userData = userDoc.data() else {
                print("⚠️ User document not found")
                return
            }
            
            // Cache all user data for fast access
            if let displayName = userData["displayName"] as? String {
                UserDefaults.standard.set(displayName, forKey: "currentUserDisplayName")
                print("✅ Cached displayName: \(displayName)")
            }
            
            if let username = userData["username"] as? String {
                UserDefaults.standard.set(username, forKey: "currentUserUsername")
                print("✅ Cached username: \(username)")
            }
            
            if let initials = userData["initials"] as? String {
                UserDefaults.standard.set(initials, forKey: "currentUserInitials")
                print("✅ Cached initials: \(initials)")
            }
            
            if let profileImageURL = userData["profileImageURL"] as? String, !profileImageURL.isEmpty {
                UserDefaults.standard.set(profileImageURL, forKey: "currentUserProfileImageURL")
                print("✅ Cached profileImageURL: \(profileImageURL)")
            } else {
                // Clear cached image URL if none exists
                UserDefaults.standard.removeObject(forKey: "currentUserProfileImageURL")
                print("ℹ️ No profile image URL to cache")
            }
            
            print("✅ User profile data cached successfully")
            
        } catch {
            print("❌ Failed to cache user profile: \(error)")
        }
    }
    
    /// Update the cached profile image URL (call this when user updates their profile picture)
    func updateCachedProfileImage(url: String?) {
        if let url = url, !url.isEmpty {
            UserDefaults.standard.set(url, forKey: "currentUserProfileImageURL")
            print("✅ Updated cached profile image URL: \(url)")
        } else {
            UserDefaults.standard.removeObject(forKey: "currentUserProfileImageURL")
            print("ℹ️ Removed cached profile image URL")
        }
    }
    
    /// Clear all cached user data (call on logout)
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: "currentUserDisplayName")
        UserDefaults.standard.removeObject(forKey: "currentUserUsername")
        UserDefaults.standard.removeObject(forKey: "currentUserInitials")
        UserDefaults.standard.removeObject(forKey: "currentUserProfileImageURL")
        print("✅ Cleared cached user profile data")
    }
    
    /// Get cached profile image URL
    var cachedProfileImageURL: String? {
        UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
    }
}
