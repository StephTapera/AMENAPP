//
//  ProfilePictureDebugHelper.swift
//  AMENAPP
//
//  Debug utilities for testing profile picture functionality
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

#if DEBUG
class ProfilePictureDebugHelper {
    static let shared = ProfilePictureDebugHelper()
    
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// Print current user's cached profile data
    func printCachedProfileData() {
        dlog("🔍 === CACHED PROFILE DATA ===")
        dlog("Display Name: \(UserDefaults.standard.string(forKey: "currentUserDisplayName") ?? "nil")")
        dlog("Username: \(UserDefaults.standard.string(forKey: "currentUserUsername") ?? "nil")")
        dlog("Initials: \(UserDefaults.standard.string(forKey: "currentUserInitials") ?? "nil")")
        dlog("Profile Image URL: \(UserDefaults.standard.string(forKey: "currentUserProfileImageURL") ?? "nil")")
        dlog("=============================")
    }
    
    /// Check if a specific post has profile image URL
    func checkPost(postId: String) async {
        do {
            let doc = try await db.collection("posts").document(postId).getDocument()
            
            guard let data = doc.data() else {
                dlog("❌ Post not found: \(postId)")
                return
            }
            
            dlog("🔍 === POST DATA ===")
            dlog("Author ID: \(data["authorId"] as? String ?? "nil")")
            dlog("Author Name: \(data["authorName"] as? String ?? "nil")")
            dlog("Profile Image URL: \(data["authorProfileImageURL"] as? String ?? "nil")")
            dlog("Has Profile Image: \(data["authorProfileImageURL"] != nil)")
            dlog("===================")
            
        } catch {
            dlog("❌ Error fetching post: \(error)")
        }
    }
    
    /// Get statistics on posts with/without profile images
    func getProfileImageStats() async {
        do {
            let snapshot = try await db.collection("posts").getDocuments()
            
            var withImage = 0
            var withoutImage = 0
            var emptyImage = 0
            
            for doc in snapshot.documents {
                let data = doc.data()
                
                if let imageURL = data["authorProfileImageURL"] as? String {
                    if imageURL.isEmpty {
                        emptyImage += 1
                    } else {
                        withImage += 1
                    }
                } else {
                    withoutImage += 1
                }
            }
            
            let total = snapshot.documents.count
            
            dlog("📊 === PROFILE IMAGE STATISTICS ===")
            dlog("Total Posts: \(total)")
            dlog("With Profile Image: \(withImage) (\(withImage * 100 / max(total, 1))%)")
            dlog("Without Profile Image: \(withoutImage) (\(withoutImage * 100 / max(total, 1))%)")
            dlog("Empty Profile Image: \(emptyImage) (\(emptyImage * 100 / max(total, 1))%)")
            dlog("==================================")
            
        } catch {
            dlog("❌ Error getting stats: \(error)")
        }
    }
    
    /// Check current user's profile in Firestore
    func checkCurrentUserProfile() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            dlog("❌ No authenticated user")
            return
        }
        
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            
            guard let data = doc.data() else {
                dlog("❌ User document not found")
                return
            }
            
            dlog("🔍 === FIRESTORE USER DATA ===")
            dlog("User ID: \(userId)")
            dlog("Display Name: \(data["displayName"] as? String ?? "nil")")
            dlog("Username: \(data["username"] as? String ?? "nil")")
            dlog("Initials: \(data["initials"] as? String ?? "nil")")
            dlog("Profile Image URL: \(data["profileImageURL"] as? String ?? "nil")")
            dlog("Has Profile Image: \(data["profileImageURL"] != nil)")
            dlog("==============================")
            
        } catch {
            dlog("❌ Error fetching user: \(error)")
        }
    }
    
    /// Force re-cache current user profile
    func forceCacheRefresh() async {
        dlog("🔄 Forcing profile cache refresh...")
        await UserProfileImageCache.shared.cacheCurrentUserProfile()
        printCachedProfileData()
    }
    
    /// Force migration for current user's posts
    func forceMigrateCurrentUserPosts() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            dlog("❌ No authenticated user")
            return
        }
        
        do {
            dlog("🔄 Forcing migration for current user's posts...")
            try await PostProfileImageMigration.shared.migratePostsForUser(userId: userId)
            dlog("✅ Migration complete")
        } catch {
            dlog("❌ Migration failed: \(error)")
        }
    }
    
    /// Reset migration flags (for testing)
    func resetMigrationFlags() {
        UserDefaults.standard.removeObject(forKey: "hasRunPostProfileImageMigration_v1")
        UserDefaults.standard.removeObject(forKey: "hasRunUserSearchMigration_v1")
        dlog("✅ Migration flags reset - restart app to run migrations again")
    }
    
    /// Complete diagnostic check
    func runFullDiagnostic() async {
        dlog("\n🔍 === PROFILE PICTURE DIAGNOSTIC ===\n")
        
        dlog("1. Cached Profile Data:")
        printCachedProfileData()
        
        dlog("\n2. Firestore User Profile:")
        await checkCurrentUserProfile()
        
        dlog("\n3. Profile Image Statistics:")
        await getProfileImageStats()
        
        dlog("\n4. Migration Status:")
        let hasRun = UserDefaults.standard.bool(forKey: "hasRunPostProfileImageMigration_v1")
        dlog("Migration has run: \(hasRun ? "✅ Yes" : "❌ No")")
        
        dlog("\n====================================\n")
    }
}
#endif

// MARK: - SwiftUI Debug View

#if DEBUG
import SwiftUI

struct ProfilePictureDebugView: View {
    @State private var isRunning = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("Diagnostics") {
                    Button("Run Full Diagnostic") {
                        runDiagnostic()
                    }
                    
                    Button("Print Cached Data") {
                        ProfilePictureDebugHelper.shared.printCachedProfileData()
                    }
                    
                    Button("Check User Profile") {
                        checkProfile()
                    }
                    
                    Button("Get Statistics") {
                        getStats()
                    }
                }
                
                Section("Actions") {
                    Button("Force Cache Refresh") {
                        forceCacheRefresh()
                    }
                    
                    Button("Migrate My Posts") {
                        migratePosts()
                    }
                }
                
                Section("Reset (Dangerous)") {
                    Button("Reset Migration Flags", role: .destructive) {
                        ProfilePictureDebugHelper.shared.resetMigrationFlags()
                    }
                }
            }
            .navigationTitle("Profile Picture Debug")
            .overlay {
                if isRunning {
                    ProgressView("Running...")
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(radius: 8)
                }
            }
        }
    }
    
    private func runDiagnostic() {
        Task {
            isRunning = true
            await ProfilePictureDebugHelper.shared.runFullDiagnostic()
            isRunning = false
        }
    }
    
    private func checkProfile() {
        Task {
            isRunning = true
            await ProfilePictureDebugHelper.shared.checkCurrentUserProfile()
            isRunning = false
        }
    }
    
    private func getStats() {
        Task {
            isRunning = true
            await ProfilePictureDebugHelper.shared.getProfileImageStats()
            isRunning = false
        }
    }
    
    private func forceCacheRefresh() {
        Task {
            isRunning = true
            await ProfilePictureDebugHelper.shared.forceCacheRefresh()
            isRunning = false
        }
    }
    
    private func migratePosts() {
        Task {
            isRunning = true
            await ProfilePictureDebugHelper.shared.forceMigrateCurrentUserPosts()
            isRunning = false
        }
    }
}
#endif
