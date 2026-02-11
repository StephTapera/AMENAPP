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
        print("🔍 === CACHED PROFILE DATA ===")
        print("Display Name: \(UserDefaults.standard.string(forKey: "currentUserDisplayName") ?? "nil")")
        print("Username: \(UserDefaults.standard.string(forKey: "currentUserUsername") ?? "nil")")
        print("Initials: \(UserDefaults.standard.string(forKey: "currentUserInitials") ?? "nil")")
        print("Profile Image URL: \(UserDefaults.standard.string(forKey: "currentUserProfileImageURL") ?? "nil")")
        print("=============================")
    }
    
    /// Check if a specific post has profile image URL
    func checkPost(postId: String) async {
        do {
            let doc = try await db.collection("posts").document(postId).getDocument()
            
            guard let data = doc.data() else {
                print("❌ Post not found: \(postId)")
                return
            }
            
            print("🔍 === POST DATA ===")
            print("Author ID: \(data["authorId"] as? String ?? "nil")")
            print("Author Name: \(data["authorName"] as? String ?? "nil")")
            print("Profile Image URL: \(data["authorProfileImageURL"] as? String ?? "nil")")
            print("Has Profile Image: \(data["authorProfileImageURL"] != nil)")
            print("===================")
            
        } catch {
            print("❌ Error fetching post: \(error)")
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
            
            print("📊 === PROFILE IMAGE STATISTICS ===")
            print("Total Posts: \(total)")
            print("With Profile Image: \(withImage) (\(withImage * 100 / max(total, 1))%)")
            print("Without Profile Image: \(withoutImage) (\(withoutImage * 100 / max(total, 1))%)")
            print("Empty Profile Image: \(emptyImage) (\(emptyImage * 100 / max(total, 1))%)")
            print("==================================")
            
        } catch {
            print("❌ Error getting stats: \(error)")
        }
    }
    
    /// Check current user's profile in Firestore
    func checkCurrentUserProfile() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ No authenticated user")
            return
        }
        
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            
            guard let data = doc.data() else {
                print("❌ User document not found")
                return
            }
            
            print("🔍 === FIRESTORE USER DATA ===")
            print("User ID: \(userId)")
            print("Display Name: \(data["displayName"] as? String ?? "nil")")
            print("Username: \(data["username"] as? String ?? "nil")")
            print("Initials: \(data["initials"] as? String ?? "nil")")
            print("Profile Image URL: \(data["profileImageURL"] as? String ?? "nil")")
            print("Has Profile Image: \(data["profileImageURL"] != nil)")
            print("==============================")
            
        } catch {
            print("❌ Error fetching user: \(error)")
        }
    }
    
    /// Force re-cache current user profile
    func forceCacheRefresh() async {
        print("🔄 Forcing profile cache refresh...")
        await UserProfileImageCache.shared.cacheCurrentUserProfile()
        printCachedProfileData()
    }
    
    /// Force migration for current user's posts
    func forceMigrateCurrentUserPosts() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ No authenticated user")
            return
        }
        
        do {
            print("🔄 Forcing migration for current user's posts...")
            try await PostProfileImageMigration.shared.migratePostsForUser(userId: userId)
            print("✅ Migration complete")
        } catch {
            print("❌ Migration failed: \(error)")
        }
    }
    
    /// Reset migration flags (for testing)
    func resetMigrationFlags() {
        UserDefaults.standard.removeObject(forKey: "hasRunPostProfileImageMigration_v1")
        UserDefaults.standard.removeObject(forKey: "hasRunUserSearchMigration_v1")
        print("✅ Migration flags reset - restart app to run migrations again")
    }
    
    /// Complete diagnostic check
    func runFullDiagnostic() async {
        print("\n🔍 === PROFILE PICTURE DIAGNOSTIC ===\n")
        
        print("1. Cached Profile Data:")
        printCachedProfileData()
        
        print("\n2. Firestore User Profile:")
        await checkCurrentUserProfile()
        
        print("\n3. Profile Image Statistics:")
        await getProfileImageStats()
        
        print("\n4. Migration Status:")
        let hasRun = UserDefaults.standard.bool(forKey: "hasRunPostProfileImageMigration_v1")
        print("Migration has run: \(hasRun ? "✅ Yes" : "❌ No")")
        
        print("\n====================================\n")
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
