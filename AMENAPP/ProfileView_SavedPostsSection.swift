//
//  ProfileView_SavedPostsSection.swift
//  AMENAPP
//
//  ADD THIS TO YOUR PROFILEVIEW
//

import SwiftUI

/*
 
 ╔═══════════════════════════════════════════════════════════╗
 ║                                                           ║
 ║   🔖 COPY THIS CODE INTO YOUR PROFILEVIEW 🔖             ║
 ║                                                           ║
 ╚═══════════════════════════════════════════════════════════╝
 
 
 STEP 1: Open your ProfileView.swift file
 
 STEP 2: Find the List or VStack where you have your profile sections
 
 STEP 3: Add this code as a new Section:
 
 */

// ═══════════════════════════════════════════════════════════
// COPY FROM HERE 👇
// ═══════════════════════════════════════════════════════════

extension View {
    func addSavedPostsSection() -> some View {
        self
    }
}

// ADD THIS SECTION TO YOUR PROFILEVIEW LIST:
struct SavedPostsProfileSection: View {
    var body: some View {
        Section {
            SavedPostsRow()
        } header: {
            Text("My Content")
                .font(.custom("OpenSans-SemiBold", size: 14))
                .textCase(nil)
        }
    }
}

// ═══════════════════════════════════════════════════════════
// COPY TO HERE 👆
// ═══════════════════════════════════════════════════════════

/*
 
 EXAMPLE: Here's how your ProfileView should look after adding it:
 
 */

struct ProfileView_Example: View {
    var body: some View {
        NavigationStack {
            List {
                // Your existing sections...
                Section {
                    Text("Profile Header")
                } header: {
                    Text("Profile")
                }
                
                Section {
                    Text("Settings")
                } header: {
                    Text("Settings")
                }
                
                // 👇 ADD THIS NEW SECTION 👇
                SavedPostsProfileSection()
                // 👆 THAT'S IT! 👆
                
                // More sections...
            }
            .navigationTitle("Profile")
        }
    }
}

/*
 
 ══════════════════════════════════════════════════════════════
                    🎯 ALTERNATIVE: SIMPLE VERSION
 ══════════════════════════════════════════════════════════════
 
 If you want the SIMPLEST integration, just add this ONE LINE
 anywhere in your ProfileView List:
 
 */

struct ProfileView_SimplestExample: View {
    var body: some View {
        NavigationStack {
            List {
                // ... existing sections ...
                
                // 👇 ADD JUST THIS ONE LINE 👇
                SavedPostsRow()
                // 👆 DONE! 👆
                
                // ... more sections ...
            }
            .navigationTitle("Profile")
        }
    }
}

/*
 
 ══════════════════════════════════════════════════════════════
           📱 WHAT YOUR USERS WILL SEE IN PROFILE
 ══════════════════════════════════════════════════════════════
 
 
 ┌────────────────────────────────────────────────┐
 │                                                │
 │  Profile                                       │
 │                                                │
 │  ┌──────────────────────────────────────────┐ │
 │  │  👤  Profile Picture                     │ │
 │  │      John Doe                            │ │
 │  └──────────────────────────────────────────┘ │
 │                                                │
 │  My Content                                    │
 │  ┌──────────────────────────────────────────┐ │
 │  │  🔖  Saved Posts                    12 › │ │ ← NEW!
 │  └──────────────────────────────────────────┘ │
 │                                                │
 │  Settings                                      │
 │  ┌──────────────────────────────────────────┐ │
 │  │  ⚙️  Preferences                        › │ │
 │  └──────────────────────────────────────────┘ │
 │                                                │
 └────────────────────────────────────────────────┘
 
 
 When tapped → Opens full SavedPostsView
 
 
 ══════════════════════════════════════════════════════════════
                        🚀 YOU'RE DONE!
 ══════════════════════════════════════════════════════════════
 
 After adding SavedPostsRow() to your ProfileView:
 
 1. Build and run ✅
 2. Go to Profile tab ✅
 3. See "Saved Posts" row ✅
 4. Tap it to open full view ✅
 
 That's all you need to do! The bookmark functionality in PostCard
 is already working - this just adds the UI to view saved posts.
 
 */

#Preview("Profile Example") {
    ProfileView_Example()
}

#Preview("Simplest Example") {
    ProfileView_SimplestExample()
}

#Preview("Just the Section") {
    List {
        SavedPostsProfileSection()
    }
}
