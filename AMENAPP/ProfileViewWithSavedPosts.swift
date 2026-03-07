//
//  ProfileViewWithSavedPosts.swift
//  AMENAPP
//
//  DROP-IN REPLACEMENT FOR YOUR EXISTING PROFILEVIEW
//  OR ADD SAVEDPOSTSROW() TO YOUR CURRENT PROFILEVIEW
//

import SwiftUI

/*
 
 ╔════════════════════════════════════════════════════════════╗
 ║                                                            ║
 ║     🎯 2 WAYS TO ADD SAVED POSTS TO YOUR PROFILE 🎯      ║
 ║                                                            ║
 ╚════════════════════════════════════════════════════════════╝
 
 
 OPTION 1: FIND YOUR PROFILEVIEW.SWIFT AND ADD THIS LINE
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 
 Just add this ONE line anywhere in your ProfileView's List:
 
     SavedPostsRow()
 
 Done! That's it!
 
 
 OPTION 2: USE THE FLOATING ACCESS BUTTON
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 
 If you can't find ProfileView, add the floating button to HomeView
 or any view where users spend time.
 
 See SavedPostsFloatingButton below.
 
 */

// MARK: - Floating Saved Posts Button

/// Add this to your HomeView, FeedView, or any main view
/// This gives users quick access to saved posts from anywhere
struct SavedPostsFloatingButton: View {
    @State private var showSavedPosts = false
    @ObservedObject private var savedPostsService = RealtimeSavedPostsService.shared
    @State private var savedCount = 0
    
    var body: some View {
        Button {
            showSavedPosts = true
        } label: {
            ZStack(alignment: .topTrailing) {
                // Main button
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .shadow(color: .blue.opacity(0.4), radius: 12, y: 6)
                
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                
                // Badge count
                if savedCount > 0 {
                    Text("\(savedCount)")
                        .font(.custom("OpenSans-Bold", size: 11))
                        .foregroundStyle(.white)
                        .padding(.horizontal, savedCount > 9 ? 6 : 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.red)
                        )
                        .offset(x: 8, y: -8)
                }
            }
        }
        .sheet(isPresented: $showSavedPosts) {
            NavigationStack {
                SavedPostsView()
            }
        }
        .task {
            await loadCount()
        }
    }
    
    private func loadCount() async {
        do {
            savedCount = try await savedPostsService.getSavedPostsCount()
        } catch {
            print("❌ Error loading saved count: \(error)")
        }
    }
}

// MARK: - Example: Add Floating Button to HomeView

/*
 
 Add this to your HomeView (or any view):
 
 */

struct HomeView_WithSavedPostsExample: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Your existing HomeView content
            ScrollView {
                Text("Your feed content here")
            }
            
            // 👇 ADD THIS FLOATING BUTTON 👇
            SavedPostsFloatingButton()
                .padding()
            // 👆 END 👆
        }
    }
}

// MARK: - Example: Add to Sidebar/Menu

/// If you have a sidebar or menu, use this version
struct SavedPostsMenuItem: View {
    var body: some View {
        NavigationLink {
            SavedPostsView()
        } label: {
            Label("Saved Posts", systemImage: "bookmark.fill")
                .font(.custom("OpenSans-SemiBold", size: 16))
        }
    }
}

// MARK: - Example: Complete ProfileView with Saved Posts

/// Example of what a ProfileView looks like with SavedPostsRow added
struct ProfileViewExample: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    
    var body: some View {
        NavigationStack {
            List {
                // Profile header
                Section {
                    VStack(spacing: 16) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 80, height: 80)
                            .overlay(
                                Text("JD")
                                    .font(.custom("OpenSans-Bold", size: 32))
                                    .foregroundStyle(.white)
                            )
                        
                        VStack(spacing: 4) {
                            Text("John Doe")
                                .font(.custom("OpenSans-Bold", size: 22))
                            Text("@johndoe")
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
                
                // 👇 MY CONTENT SECTION WITH SAVED POSTS 👇
                Section {
                    // ADD THIS LINE TO YOUR PROFILEVIEW:
                    SavedPostsRow()
                    
                    // You can also add other content items here:
                    NavigationLink("My Posts") {
                        Text("Your Posts")
                    }
                    
                    NavigationLink("Drafts") {
                        Text("Drafts")
                    }
                } header: {
                    Text("My Content")
                }
                // 👆 END OF MY CONTENT SECTION 👆
                
                // Settings section
                Section {
                    NavigationLink("Account Settings") {
                        Text("Settings")
                    }
                    
                    NavigationLink("Privacy") {
                        Text("Privacy")
                    }
                    
                    NavigationLink("Notifications") {
                        Text("Notifications")
                    }
                } header: {
                    Text("Settings")
                }
                
                // Sign out
                Section {
                    Button("Sign Out") {
                        // authViewModel.signOut()
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Profile")
        }
    }
}

#Preview("ProfileView Example") {
    ProfileViewExample()
}

#Preview("Floating Button") {
    ZStack(alignment: .bottomTrailing) {
        Color.gray.opacity(0.1)
        SavedPostsFloatingButton()
            .padding()
    }
}

#Preview("Menu Item") {
    NavigationStack {
        List {
            SavedPostsMenuItem()
        }
    }
}

/*
 
 ╔════════════════════════════════════════════════════════════╗
 ║                                                            ║
 ║              ✅ WHAT TO DO NOW ✅                         ║
 ║                                                            ║
 ╚════════════════════════════════════════════════════════════╝
 
 
 STEP 1: Choose your integration method
 ────────────────────────────────────────
 
 A. Add to ProfileView (Best):
    → Open ProfileView.swift
    → Find the List
    → Add: SavedPostsRow()
 
 B. Add Floating Button (Easy):
    → Open HomeView.swift or main feed view
    → Wrap content in ZStack
    → Add: SavedPostsFloatingButton()
 
 C. Add to Menu/Sidebar:
    → Add: SavedPostsMenuItem()
 
 
 STEP 2: Deploy Firebase RTDB Rules
 ────────────────────────────────────────
 
 Copy from COPY_PASTE_CODE.txt:
 → Firebase Console → Realtime Database → Rules
 → Paste → Publish
 
 
 STEP 3: Test
 ────────────────────────────────────────
 
 1. Build and run
 2. Save a post (tap bookmark icon)
 3. Open Saved Posts (from Profile or button)
 4. See your saved post ✅
 
 
 DONE! 🎉
 
 */
