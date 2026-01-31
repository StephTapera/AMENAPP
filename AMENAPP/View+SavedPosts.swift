//
//  View+SavedPosts.swift
//  AMENAPP
//
//  Created by Steph on 1/29/26.
//
//  Convenient view modifiers for integrating saved posts
//

import SwiftUI

extension View {
    /// Adds a saved posts navigation link to a view
    func savedPostsNavigationLink() -> some View {
        NavigationLink {
            SavedPostsView()
        } label: {
            self
        }
    }
}

// MARK: - Example Usage Snippets

/*
 
 /// Example 1: Add to Profile View
 
 struct ProfileView: View {
     var body: some View {
         NavigationStack {
             List {
                 Section("My Content") {
                     SavedPostsRow()
                     
                     // Or use the compact version:
                     // SavedPostsListCompact()
                 }
             }
             .navigationTitle("Profile")
         }
     }
 }
 
 
 /// Example 2: Add to Tab Bar
 
 struct MainTabView: View {
     var body: some View {
         TabView {
             FeedView()
                 .tabItem { Label("Feed", systemImage: "house") }
             
             SavedPostsView()
                 .tabItem { Label("Saved", systemImage: "bookmark") }
             
             ProfileView()
                 .tabItem { Label("Profile", systemImage: "person") }
         }
     }
 }
 
 
 /// Example 3: Add to Dashboard with Quick Access
 
 struct DashboardView: View {
     var body: some View {
         ScrollView {
             VStack(spacing: 16) {
                 // Quick access buttons
                 HStack(spacing: 16) {
                     SavedPostsQuickAccessButton()
                     PrayerRequestsQuickAccessButton()
                 }
                 .padding(.horizontal)
                 
                 // ... rest of dashboard
             }
         }
     }
 }
 
 
 /// Example 4: Add to Settings/Menu
 
 struct SettingsView: View {
     var body: some View {
         List {
             Section("Content") {
                 NavigationLink {
                     SavedPostsView()
                 } label: {
                     HStack {
                         Image(systemName: "bookmark.fill")
                             .foregroundStyle(.blue)
                         Text("Saved Posts")
                     }
                 }
             }
         }
     }
 }
 
 
 /// Example 5: Floating Action Button
 
 struct FeedView: View {
     @State private var showSavedPosts = false
     
     var body: some View {
         ZStack(alignment: .bottomTrailing) {
             // Main feed content
             ScrollView {
                 // ... posts
             }
             
             // Floating saved posts button
             Button {
                 showSavedPosts = true
             } label: {
                 Image(systemName: "bookmark.fill")
                     .font(.system(size: 20, weight: .semibold))
                     .foregroundStyle(.white)
                     .frame(width: 56, height: 56)
                     .background(Color.blue)
                     .clipShape(Circle())
                     .shadow(radius: 4)
             }
             .padding()
             .sheet(isPresented: $showSavedPosts) {
                 NavigationStack {
                     SavedPostsView()
                 }
             }
         }
     }
 }
 
 */
