//
//  PostsManager+RealtimeListeners.swift
//  AMENAPP
//
//  Extension to add real-time listening capabilities to PostsManager
//

import Foundation
import SwiftUI

/// Extension to PostsManager for real-time listener management
extension PostsManager {
    
    /// Start listening to posts for a specific category
    /// This enables real-time updates when posts are created, modified, or deleted
    func startListening(for category: Post.PostCategory) {
        dlog("📡 PostsManager: Starting real-time listener for \(category.rawValue)")
        FirebasePostService.shared.startListening(category: category)
    }
    
    /// Stop all real-time listeners
    /// Call this when you want to stop receiving updates (e.g., when view disappears)
    func stopListening() {
        dlog("📡 PostsManager: Stopping all real-time listeners")
        FirebasePostService.shared.stopListening()
    }
    
    /// Start listening to all categories at once
    /// Useful for main feed views that show posts from all categories
    func startListeningToAllCategories() {
        dlog("📡 PostsManager: Starting real-time listener for ALL categories")
        FirebasePostService.shared.startListening(category: nil)
    }
}

// MARK: - View Extension for Easy Integration

extension View {
    /// Convenience modifier to start listening to posts for a specific category
    /// Usage: .listenToPosts(for: .openTable)
    func listenToPosts(for category: Post.PostCategory) -> some View {
        self.task {
            PostsManager.shared.startListening(for: category)
        }
    }
    
    /// Convenience modifier to listen to all post categories
    /// Usage: .listenToAllPosts()
    func listenToAllPosts() -> some View {
        self.task {
            PostsManager.shared.startListeningToAllCategories()
        }
    }
}

// MARK: - Usage Examples

/*
 
 Example 1: In OpenTableView
 -----------------------------------------
 struct OpenTableView: View {
     @StateObject private var postsManager = PostsManager.shared
     
     var body: some View {
         ScrollView {
             // your view code
         }
         .listenToPosts(for: .openTable) // ✅ One line!
     }
 }
 
 
 Example 2: In TestimoniesView
 -----------------------------------------
 struct TestimoniesView: View {
     @StateObject private var postsManager = PostsManager.shared
     
     var body: some View {
         ScrollView {
             // your view code
         }
         .listenToPosts(for: .testimonies) // ✅ One line!
     }
 }
 
 
 Example 3: In PrayerView
 -----------------------------------------
 struct PrayerView: View {
     @StateObject private var postsManager = PostsManager.shared
     
     var body: some View {
         ScrollView {
             // your view code
         }
         .listenToPosts(for: .prayer) // ✅ One line!
     }
 }
 
 
 Example 4: Manual Control
 -----------------------------------------
 struct CustomView: View {
     @StateObject private var postsManager = PostsManager.shared
     
     var body: some View {
         ScrollView {
             // your view code
         }
         .task {
             // ✅ Start listener manually
             postsManager.startListening(for: .openTable)
         }
         .onDisappear {
             // ✅ Optional: Stop listener when leaving view
             // (not required - .task auto-cancels)
             postsManager.stopListening()
         }
     }
 }
 
 */
