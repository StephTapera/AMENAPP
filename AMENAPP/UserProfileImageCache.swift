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
            dlog("⚠️ No authenticated user to cache profile")
            return
        }
        
        do {
            let userDoc = try await db.collection("users").document(userId).getDocument()
            
            guard let userData = userDoc.data() else {
                dlog("⚠️ User document not found")
                return
            }
            
            // Cache all user data for fast access
            if let displayName = userData["displayName"] as? String {
                UserDefaults.standard.set(displayName, forKey: "currentUserDisplayName")
                dlog("✅ Cached displayName: \(displayName)")
            }
            
            if let username = userData["username"] as? String {
                UserDefaults.standard.set(username, forKey: "currentUserUsername")
                dlog("✅ Cached username: \(username)")
            }
            
            if let initials = userData["initials"] as? String {
                UserDefaults.standard.set(initials, forKey: "currentUserInitials")
                dlog("✅ Cached initials: \(initials)")
            }
            
            if let profileImageURL = userData["profileImageURL"] as? String, !profileImageURL.isEmpty {
                UserDefaults.standard.set(profileImageURL, forKey: "currentUserProfileImageURL")
                dlog("✅ Cached profileImageURL: \(profileImageURL)")
            } else {
                // Clear cached image URL if none exists
                UserDefaults.standard.removeObject(forKey: "currentUserProfileImageURL")
                dlog("ℹ️ No profile image URL to cache")
            }
            
            dlog("✅ User profile data cached successfully")
            
        } catch {
            dlog("❌ Failed to cache user profile: \(error)")
        }
    }
    
    /// Update the cached profile image URL (call this when user updates their profile picture)
    func updateCachedProfileImage(url: String?) {
        if let url = url, !url.isEmpty {
            UserDefaults.standard.set(url, forKey: "currentUserProfileImageURL")
            dlog("✅ Updated cached profile image URL: \(url)")
        } else {
            UserDefaults.standard.removeObject(forKey: "currentUserProfileImageURL")
            dlog("ℹ️ Removed cached profile image URL")
        }
    }
    
    /// Clear all cached user data (call on logout)
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: "currentUserDisplayName")
        UserDefaults.standard.removeObject(forKey: "currentUserUsername")
        UserDefaults.standard.removeObject(forKey: "currentUserInitials")
        UserDefaults.standard.removeObject(forKey: "currentUserProfileImageURL")
        dlog("✅ Cleared cached user profile data")
    }
    
    /// Get cached profile image URL
    var cachedProfileImageURL: String? {
        UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
    }
}
