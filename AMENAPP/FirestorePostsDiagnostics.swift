//
//  FirestorePostsDiagnostics.swift
//  AMENAPP
//
//  Created by AI Assistant on 2/5/26.
//
//  Diagnostic tools for debugging user profile posts
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Diagnostic utilities for debugging Firestore posts
class FirestorePostsDiagnostics {
    
    static let shared = FirestorePostsDiagnostics()
    private let db = Firestore.firestore()
    
    private init() {}
    
    // MARK: - Diagnostic Functions
    
    /// Run comprehensive diagnostics on user posts
    /// Call this from your UserProfileView to debug why posts aren't showing
    @MainActor
    func diagnoseUserPosts(userId: String) async {
        print("🔍 ========== STARTING POST DIAGNOSTICS ==========")
        print("🔍 User ID: \(userId)")
        print("")
        
        // Step 1: Check authentication
        await checkAuthentication()
        
        // Step 2: Check if user document exists
        await checkUserExists(userId: userId)
        
        // Step 3: Query all posts by this user (no filters)
        await queryAllUserPosts(userId: userId)
        
        // Step 4: Query original posts (with isRepost filter)
        await queryOriginalPosts(userId: userId)
        
        // Step 5: Query reposts
        await queryReposts(userId: userId)
        
        // Step 6: Check indexes
        await checkIndexes()
        
        print("")
        print("🔍 ========== DIAGNOSTICS COMPLETE ==========")
    }
    
    // MARK: - Individual Diagnostic Steps
    
    @MainActor
    private func checkAuthentication() async {
        print("📱 Step 1: Checking Authentication")
        
        guard let currentUser = Auth.auth().currentUser else {
            print("   ❌ NOT AUTHENTICATED - User must sign in to view profiles")
            return
        }
        
        dlog("   ✅ Authenticated (uid redacted)")
        dlog("   Email: [REDACTED]")
        print("")
    }
    
    @MainActor
    private func checkUserExists(userId: String) async {
        print("👤 Step 2: Checking User Document")
        
        do {
            let userDoc = try await db.collection("users").document(userId).getDocument()
            
            if userDoc.exists {
                print("   ✅ User document exists")
                if let data = userDoc.data() {
                    print("   Name: \(data["displayName"] as? String ?? "Unknown")")
                    print("   Username: @\(data["username"] as? String ?? "unknown")")
                    print("   Posts Count: \(data["postsCount"] as? Int ?? 0)")
                }
            } else {
                print("   ❌ User document does NOT exist")
                print("      This user may have been deleted or the ID is incorrect")
            }
        } catch {
            print("   ❌ Error fetching user document: \(error)")
        }
        
        print("")
    }
    
    @MainActor
    private func queryAllUserPosts(userId: String) async {
        print("📊 Step 3: Querying ALL Posts (No Filters)")
        
        do {
            let snapshot = try await db.collection("posts")
                .whereField("authorId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
                .getDocuments()
            
            print("   ✅ Found \(snapshot.documents.count) total posts")
            
            if snapshot.documents.isEmpty {
                print("   ⚠️ No posts found for this user")
                print("      Possible reasons:")
                print("      1. User hasn't created any posts")
                print("      2. authorId in posts doesn't match '\(userId)'")
                print("      3. Firestore security rules are blocking the query")
            } else {
                // Analyze posts
                var categoryBreakdown: [String: Int] = [:]
                var repostCount = 0
                var originalCount = 0
                
                for doc in snapshot.documents {
                    let data = doc.data()
                    let category = data["category"] as? String ?? "unknown"
                    let isRepost = data["isRepost"] as? Bool ?? false
                    
                    categoryBreakdown[category, default: 0] += 1
                    
                    if isRepost {
                        repostCount += 1
                    } else {
                        originalCount += 1
                    }
                }
                
                print("   ")
                print("   📊 Post Breakdown:")
                print("      - Original posts: \(originalCount)")
                print("      - Reposts: \(repostCount)")
                print("   ")
                print("   📂 Category Breakdown:")
                for (category, count) in categoryBreakdown.sorted(by: { $0.key < $1.key }) {
                    print("      - \(category): \(count)")
                }
                
                // Show first 3 posts as examples
                print("   ")
                print("   📝 Sample Posts:")
                for (index, doc) in snapshot.documents.prefix(3).enumerated() {
                    let data = doc.data()
                    print("      Post \(index + 1):")
                    print("         ID: \(doc.documentID)")
                    print("         Category: \(data["category"] as? String ?? "unknown")")
                    print("         Is Repost: \(data["isRepost"] as? Bool ?? false)")
                    print("         Content: \((data["content"] as? String ?? "").prefix(50))...")
                    print("")
                }
            }
        } catch {
            print("   ❌ Error querying posts: \(error)")
            
            if let nsError = error as NSError? {
                print("      Error domain: \(nsError.domain)")
                print("      Error code: \(nsError.code)")
            }
        }
        
        print("")
    }
    
    @MainActor
    private func queryOriginalPosts(userId: String) async {
        print("✏️ Step 4: Querying ORIGINAL Posts (isRepost = false)")
        
        do {
            let snapshot = try await db.collection("posts")
                .whereField("authorId", isEqualTo: userId)
                .whereField("isRepost", isEqualTo: false)
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
                .getDocuments()
            
            print("   ✅ Found \(snapshot.documents.count) original posts")
            
            if snapshot.documents.isEmpty {
                print("   ⚠️ No original posts found")
                print("      This means all posts have isRepost=true")
            } else {
                var categoryBreakdown: [String: Int] = [:]
                
                for doc in snapshot.documents {
                    let data = doc.data()
                    let category = data["category"] as? String ?? "unknown"
                    categoryBreakdown[category, default: 0] += 1
                }
                
                print("   ")
                print("   📂 Category Breakdown (Original Posts):")
                for (category, count) in categoryBreakdown.sorted(by: { $0.key < $1.key }) {
                    print("      - \(category): \(count)")
                }
            }
        } catch {
            print("   ❌ Error querying original posts: \(error)")
            
            if let nsError = error as NSError?,
               nsError.domain == "FIRFirestoreErrorDomain",
               nsError.code == 9 {
                print("      ")
                print("      ⚠️ FIRESTORE INDEX REQUIRED!")
                print("      This query requires a composite index:")
                print("      Collection: posts")
                print("      Fields: authorId (Asc), isRepost (Asc), createdAt (Desc)")
                print("      ")
                print("      The FirebasePostService will automatically use a fallback query.")
            }
        }
        
        print("")
    }
    
    @MainActor
    private func queryReposts(userId: String) async {
        print("🔄 Step 5: Querying REPOSTS (isRepost = true)")
        
        do {
            let snapshot = try await db.collection("posts")
                .whereField("authorId", isEqualTo: userId)
                .whereField("isRepost", isEqualTo: true)
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
                .getDocuments()
            
            print("   ✅ Found \(snapshot.documents.count) reposts")
            
            if snapshot.documents.count > 0 {
                print("   ")
                print("   📝 Sample Reposts:")
                for (index, doc) in snapshot.documents.prefix(3).enumerated() {
                    let data = doc.data()
                    print("      Repost \(index + 1):")
                    print("         Original Author: \(data["originalAuthorName"] as? String ?? "Unknown")")
                    print("         Content: \((data["content"] as? String ?? "").prefix(50))...")
                    print("")
                }
            }
        } catch {
            print("   ❌ Error querying reposts: \(error)")
        }
        
        print("")
    }
    
    @MainActor
    private func checkIndexes() async {
        print("🔧 Step 6: Index Recommendations")
        print("   ")
        print("   For optimal performance, ensure these indexes exist:")
        print("   ")
        print("   1. Posts Collection - Original Posts Query")
        print("      Fields: authorId (Asc), isRepost (Asc), createdAt (Desc)")
        print("   ")
        print("   2. Posts Collection - Reposts Query")
        print("      Fields: authorId (Asc), isRepost (Asc), createdAt (Desc)")
        print("   ")
        print("   Create indexes at:")
        print("   Firebase Console → Firestore → Indexes")
        print("")
    }
    
    // MARK: - Quick Test
    
    /// Create a test post to verify post creation works
    @MainActor
    func createTestPost(category: String = "openTable") async {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            print("❌ Not authenticated - cannot create test post")
            return
        }
        
        guard let userName = Auth.auth().currentUser?.displayName else {
            print("❌ User has no display name")
            return
        }
        
        let testPost: [String: Any] = [
            "authorId": currentUserId,
            "authorName": userName,
            "authorInitials": String(userName.prefix(2)).uppercased(),
            "content": "TEST POST - This is a test post created at \(Date()). If you see this on your profile, post fetching is working!",
            "category": category,
            "isRepost": false,
            "createdAt": Date(),
            "amenCount": 0,
            "commentCount": 0,
            "repostCount": 0,
            "lightbulbCount": 0,
            "amenUserIds": [],
            "lightbulbUserIds": [],
            "visibility": "everyone",
            "allowComments": true
        ]
        
        do {
            let docRef = try await db.collection("posts").addDocument(data: testPost)
            print("✅ Test post created successfully!")
            print("   Post ID: \(docRef.documentID)")
            print("   Category: \(category)")
            print("   Author: \(userName) (\(currentUserId))")
            print("")
            print("   Now check your profile to see if this post appears!")
        } catch {
            print("❌ Failed to create test post: \(error)")
        }
    }
}

// MARK: - SwiftUI Helper View

import SwiftUI

/// Diagnostic button to add to your profile view for testing
struct DiagnosticsButton: View {
    let userId: String
    
    var body: some View {
        Menu {
            Button("Run Diagnostics") {
                Task {
                    await FirestorePostsDiagnostics.shared.diagnoseUserPosts(userId: userId)
                }
            }
            
            Button("Create Test Post (OpenTable)") {
                Task {
                    await FirestorePostsDiagnostics.shared.createTestPost(category: "openTable")
                }
            }
            
            Button("Create Test Post (Testimonies)") {
                Task {
                    await FirestorePostsDiagnostics.shared.createTestPost(category: "testimonies")
                }
            }
            
            Button("Create Test Post (Prayer)") {
                Task {
                    await FirestorePostsDiagnostics.shared.createTestPost(category: "prayer")
                }
            }
        } label: {
            HStack {
                Image(systemName: "ant.circle")
                Text("Debug")
            }
            .font(.custom("OpenSans-SemiBold", size: 14))
        }
    }
}

// MARK: - Usage Example
/*
 
 To use this diagnostic tool, add this to your UserProfileView:
 
 1. In the toolbar:
 
 .toolbar {
     ToolbarItem(placement: .topBarTrailing) {
         #if DEBUG
         DiagnosticsButton(userId: userId)
         #endif
     }
 }
 
 2. Or add a hidden gesture:
 
 .onLongPressGesture(minimumDuration: 2.0) {
     Task {
         await FirestorePostsDiagnostics.shared.diagnoseUserPosts(userId: userId)
     }
 }
 
 3. Or call directly in code:
 
 Task {
     await FirestorePostsDiagnostics.shared.diagnoseUserPosts(userId: "user123")
 }
 
 */
