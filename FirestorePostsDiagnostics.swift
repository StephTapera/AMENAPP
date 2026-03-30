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
        dlog("🔍 ========== STARTING POST DIAGNOSTICS ==========")
        dlog("🔍 User ID: \(userId)")
        dlog("")
        
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
        
        dlog("")
        dlog("🔍 ========== DIAGNOSTICS COMPLETE ==========")
    }
    
    // MARK: - Individual Diagnostic Steps
    
    @MainActor
    private func checkAuthentication() async {
        dlog("📱 Step 1: Checking Authentication")
        
        guard Auth.auth().currentUser != nil else {
            dlog("   ❌ NOT AUTHENTICATED - User must sign in to view profiles")
            return
        }
        
        dlog("   ✅ Authenticated (uid redacted)")
        dlog("   Email: [REDACTED]")
        dlog("")
    }
    
    @MainActor
    private func checkUserExists(userId: String) async {
        dlog("👤 Step 2: Checking User Document")
        
        do {
            let userDoc = try await db.collection("users").document(userId).getDocument()
            
            if userDoc.exists {
                dlog("   ✅ User document exists")
                if let data = userDoc.data() {
                    dlog("   Name: \(data["displayName"] as? String ?? "Unknown")")
                    dlog("   Username: @\(data["username"] as? String ?? "unknown")")
                    dlog("   Posts Count: \(data["postsCount"] as? Int ?? 0)")
                }
            } else {
                dlog("   ❌ User document does NOT exist")
                dlog("      This user may have been deleted or the ID is incorrect")
            }
        } catch {
            dlog("   ❌ Error fetching user document: \(error)")
        }
        
        dlog("")
    }
    
    @MainActor
    private func queryAllUserPosts(userId: String) async {
        dlog("📊 Step 3: Querying ALL Posts (No Filters)")
        
        do {
            let snapshot = try await db.collection("posts")
                .whereField("authorId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
                .getDocuments()
            
            dlog("   ✅ Found \(snapshot.documents.count) total posts")
            
            if snapshot.documents.isEmpty {
                dlog("   ⚠️ No posts found for this user")
                dlog("      Possible reasons:")
                dlog("      1. User hasn't created any posts")
                dlog("      2. authorId in posts doesn't match '\(userId)'")
                dlog("      3. Firestore security rules are blocking the query")
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
                
                dlog("   ")
                dlog("   📊 Post Breakdown:")
                dlog("      - Original posts: \(originalCount)")
                dlog("      - Reposts: \(repostCount)")
                dlog("   ")
                dlog("   📂 Category Breakdown:")
                for (category, count) in categoryBreakdown.sorted(by: { $0.key < $1.key }) {
                    dlog("      - \(category): \(count)")
                }
                
                // Show first 3 posts as examples
                dlog("   ")
                dlog("   📝 Sample Posts:")
                for (index, doc) in snapshot.documents.prefix(3).enumerated() {
                    let data = doc.data()
                    dlog("      Post \(index + 1):")
                    dlog("         ID: \(doc.documentID)")
                    dlog("         Category: \(data["category"] as? String ?? "unknown")")
                    dlog("         Is Repost: \(data["isRepost"] as? Bool ?? false)")
                    dlog("         Content: \((data["content"] as? String ?? "").prefix(50))...")
                    dlog("")
                }
            }
        } catch {
            dlog("   ❌ Error querying posts: \(error)")
            
            if let nsError = error as NSError? {
                dlog("      Error domain: \(nsError.domain)")
                dlog("      Error code: \(nsError.code)")
            }
        }
        
        dlog("")
    }
    
    @MainActor
    private func queryOriginalPosts(userId: String) async {
        dlog("✏️ Step 4: Querying ORIGINAL Posts (isRepost = false)")
        
        do {
            let snapshot = try await db.collection("posts")
                .whereField("authorId", isEqualTo: userId)
                .whereField("isRepost", isEqualTo: false)
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
                .getDocuments()
            
            dlog("   ✅ Found \(snapshot.documents.count) original posts")
            
            if snapshot.documents.isEmpty {
                dlog("   ⚠️ No original posts found")
                dlog("      This means all posts have isRepost=true")
            } else {
                var categoryBreakdown: [String: Int] = [:]
                
                for doc in snapshot.documents {
                    let data = doc.data()
                    let category = data["category"] as? String ?? "unknown"
                    categoryBreakdown[category, default: 0] += 1
                }
                
                dlog("   ")
                dlog("   📂 Category Breakdown (Original Posts):")
                for (category, count) in categoryBreakdown.sorted(by: { $0.key < $1.key }) {
                    dlog("      - \(category): \(count)")
                }
            }
        } catch {
            dlog("   ❌ Error querying original posts: \(error)")
            
            if let nsError = error as NSError?,
               nsError.domain == "FIRFirestoreErrorDomain",
               nsError.code == 9 {
                dlog("      ")
                dlog("      ⚠️ FIRESTORE INDEX REQUIRED!")
                dlog("      This query requires a composite index:")
                dlog("      Collection: posts")
                dlog("      Fields: authorId (Asc), isRepost (Asc), createdAt (Desc)")
                dlog("      ")
                dlog("      The FirebasePostService will automatically use a fallback query.")
            }
        }
        
        dlog("")
    }
    
    @MainActor
    private func queryReposts(userId: String) async {
        dlog("🔄 Step 5: Querying REPOSTS (isRepost = true)")
        
        do {
            let snapshot = try await db.collection("posts")
                .whereField("authorId", isEqualTo: userId)
                .whereField("isRepost", isEqualTo: true)
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
                .getDocuments()
            
            dlog("   ✅ Found \(snapshot.documents.count) reposts")
            
            if snapshot.documents.count > 0 {
                dlog("   ")
                dlog("   📝 Sample Reposts:")
                for (index, doc) in snapshot.documents.prefix(3).enumerated() {
                    let data = doc.data()
                    dlog("      Repost \(index + 1):")
                    dlog("         Original Author: \(data["originalAuthorName"] as? String ?? "Unknown")")
                    dlog("         Content: \((data["content"] as? String ?? "").prefix(50))...")
                    dlog("")
                }
            }
        } catch {
            dlog("   ❌ Error querying reposts: \(error)")
        }
        
        dlog("")
    }
    
    @MainActor
    private func checkIndexes() async {
        dlog("🔧 Step 6: Index Recommendations")
        dlog("   ")
        dlog("   For optimal performance, ensure these indexes exist:")
        dlog("   ")
        dlog("   1. Posts Collection - Original Posts Query")
        dlog("      Fields: authorId (Asc), isRepost (Asc), createdAt (Desc)")
        dlog("   ")
        dlog("   2. Posts Collection - Reposts Query")
        dlog("      Fields: authorId (Asc), isRepost (Asc), createdAt (Desc)")
        dlog("   ")
        dlog("   Create indexes at:")
        dlog("   Firebase Console → Firestore → Indexes")
        dlog("")
    }
    
    // MARK: - Quick Test
    
    /// Create a test post to verify post creation works
    @MainActor
    func createTestPost(category: String = "openTable") async {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            dlog("❌ Not authenticated - cannot create test post")
            return
        }
        
        guard let userName = Auth.auth().currentUser?.displayName else {
            dlog("❌ User has no display name")
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
            dlog("✅ Test post created successfully!")
            dlog("   Post ID: \(docRef.documentID)")
            dlog("   Category: \(category)")
            dlog("   Author: \(userName) (\(currentUserId))")
            dlog("")
            dlog("   Now check your profile to see if this post appears!")
        } catch {
            dlog("❌ Failed to create test post: \(error)")
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
