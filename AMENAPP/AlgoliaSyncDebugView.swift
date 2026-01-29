//
//  AlgoliaSyncDebugView.swift
//  AMENAPP
//
//  Created by Steph on 1/28/26.
//
//  Debug/Admin view for testing Algolia sync
//

import SwiftUI

/// Admin view for testing and managing Algolia sync
/// Add this to your settings or debug menu
struct AlgoliaSyncDebugView: View {
    @State private var isSyncing = false
    @State private var syncMessage = ""
    @State private var syncStatus: SyncStatus = .idle
    
    enum SyncStatus {
        case idle
        case syncing
        case success
        case error
        
        var icon: String {
            switch self {
            case .idle: return "cloud.fill"
            case .syncing: return "arrow.triangle.2.circlepath"
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .idle: return .blue
            case .syncing: return .orange
            case .success: return .green
            case .error: return .red
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Status Section
                Section {
                    HStack {
                        Image(systemName: syncStatus.icon)
                            .foregroundColor(syncStatus.color)
                            .imageScale(.large)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(statusText)
                                .font(.headline)
                            if !syncMessage.isEmpty {
                                Text(syncMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if isSyncing {
                            ProgressView()
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Sync Status")
                }
                
                // Sync Actions
                Section {
                    // Sync All Data
                    Button {
                        syncAllData()
                    } label: {
                        Label("Sync All Data", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .disabled(isSyncing)
                    
                    // Sync Users Only
                    Button {
                        syncUsers()
                    } label: {
                        Label("Sync Users Only", systemImage: "person.2.fill")
                            .foregroundColor(.purple)
                    }
                    .disabled(isSyncing)
                    
                    // Sync Posts Only
                    Button {
                        syncPosts()
                    } label: {
                        Label("Sync Posts Only", systemImage: "doc.text.fill")
                            .foregroundColor(.orange)
                    }
                    .disabled(isSyncing)
                    
                } header: {
                    Text("Sync Actions")
                } footer: {
                    Text("These actions will sync your Firestore data to Algolia search indexes. Run 'Sync All Data' once to populate Algolia with existing data.")
                }
                
                // Individual Record Testing
                Section {
                    Button {
                        testUserSync()
                    } label: {
                        Label("Test User Sync", systemImage: "person.crop.circle.badge.checkmark")
                            .foregroundColor(.green)
                    }
                    .disabled(isSyncing)
                    
                    Button {
                        testPostSync()
                    } label: {
                        Label("Test Post Sync", systemImage: "doc.badge.plus")
                            .foregroundColor(.green)
                    }
                    .disabled(isSyncing)
                    
                } header: {
                    Text("Testing")
                } footer: {
                    Text("Create test records to verify sync is working correctly.")
                }
                
                // Search Testing
                Section {
                    Button {
                        testSearch()
                    } label: {
                        Label("Test Search", systemImage: "magnifyingglass")
                            .foregroundColor(.indigo)
                    }
                    .disabled(isSyncing)
                    
                } header: {
                    Text("Search Testing")
                } footer: {
                    Text("Test if Algolia search is working with your synced data.")
                }
                
                // Configuration Info
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("App ID:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(AlgoliaConfig.applicationID.prefix(8) + "...")
                                .font(.caption.monospaced())
                        }
                        
                        HStack {
                            Text("Search Key:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(AlgoliaConfig.searchAPIKey.prefix(8) + "...")
                                .font(.caption.monospaced())
                        }
                        
                        HStack {
                            Text("Write Key:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(AlgoliaConfig.writeAPIKey.prefix(8) + "...")
                                .font(.caption.monospaced())
                        }
                    }
                } header: {
                    Text("Configuration")
                }
            }
            .navigationTitle("Algolia Sync")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var statusText: String {
        switch syncStatus {
        case .idle: return "Ready to Sync"
        case .syncing: return "Syncing..."
        case .success: return "Sync Successful"
        case .error: return "Sync Failed"
        }
    }
    
    // MARK: - Sync Actions
    
    private func syncAllData() {
        isSyncing = true
        syncStatus = .syncing
        syncMessage = "Syncing all data to Algolia..."
        
        Task {
            do {
                try await AlgoliaSyncService.shared.syncAllData()
                
                await MainActor.run {
                    syncStatus = .success
                    syncMessage = "All data synced successfully!"
                    isSyncing = false
                }
                
                // Reset status after 3 seconds
                try await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    syncStatus = .idle
                    syncMessage = ""
                }
                
            } catch {
                await MainActor.run {
                    syncStatus = .error
                    syncMessage = "Error: \(error.localizedDescription)"
                    isSyncing = false
                }
            }
        }
    }
    
    private func syncUsers() {
        isSyncing = true
        syncStatus = .syncing
        syncMessage = "Syncing users to Algolia..."
        
        Task {
            do {
                try await AlgoliaSyncService.shared.bulkSyncUsers()
                
                await MainActor.run {
                    syncStatus = .success
                    syncMessage = "Users synced successfully!"
                    isSyncing = false
                }
                
                try await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    syncStatus = .idle
                    syncMessage = ""
                }
                
            } catch {
                await MainActor.run {
                    syncStatus = .error
                    syncMessage = "Error: \(error.localizedDescription)"
                    isSyncing = false
                }
            }
        }
    }
    
    private func syncPosts() {
        isSyncing = true
        syncStatus = .syncing
        syncMessage = "Syncing posts to Algolia..."
        
        Task {
            do {
                try await AlgoliaSyncService.shared.bulkSyncPosts()
                
                await MainActor.run {
                    syncStatus = .success
                    syncMessage = "Posts synced successfully!"
                    isSyncing = false
                }
                
                try await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    syncStatus = .idle
                    syncMessage = ""
                }
                
            } catch {
                await MainActor.run {
                    syncStatus = .error
                    syncMessage = "Error: \(error.localizedDescription)"
                    isSyncing = false
                }
            }
        }
    }
    
    private func testUserSync() {
        isSyncing = true
        syncStatus = .syncing
        syncMessage = "Creating test user..."
        
        Task {
            do {
                // Create a test user
                let testUserId = "test_user_\(UUID().uuidString.prefix(8))"
                let userData: [String: Any] = [
                    "displayName": "Test User",
                    "username": "testuser\(Int.random(in: 1...9999))",
                    "usernameLowercase": "testuser\(Int.random(in: 1...9999))",
                    "bio": "This is a test user for Algolia sync",
                    "followersCount": Int.random(in: 0...100),
                    "followingCount": Int.random(in: 0...50),
                    "profileImageURL": "",
                    "isVerified": false,
                    "createdAt": Date().timeIntervalSince1970
                ]
                
                // Sync to Algolia
                try await AlgoliaSyncService.shared.syncUser(userId: testUserId, userData: userData)
                
                await MainActor.run {
                    syncStatus = .success
                    syncMessage = "Test user created and synced!"
                    isSyncing = false
                }
                
                try await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    syncStatus = .idle
                    syncMessage = ""
                }
                
            } catch {
                await MainActor.run {
                    syncStatus = .error
                    syncMessage = "Error: \(error.localizedDescription)"
                    isSyncing = false
                }
            }
        }
    }
    
    private func testPostSync() {
        isSyncing = true
        syncStatus = .syncing
        syncMessage = "Creating test post..."
        
        Task {
            do {
                // Create a test post
                let testPostId = "test_post_\(UUID().uuidString.prefix(8))"
                let postData: [String: Any] = [
                    "content": "This is a test post for Algolia sync. Testing search functionality! #faith #prayer",
                    "authorId": "test_author",
                    "authorName": "Test Author",
                    "category": "testimonies",
                    "amenCount": Int.random(in: 0...50),
                    "commentCount": Int.random(in: 0...20),
                    "shareCount": 0,
                    "createdAt": Date().timeIntervalSince1970,
                    "isPublic": true
                ]
                
                // Sync to Algolia
                try await AlgoliaSyncService.shared.syncPost(postId: testPostId, postData: postData)
                
                await MainActor.run {
                    syncStatus = .success
                    syncMessage = "Test post created and synced!"
                    isSyncing = false
                }
                
                try await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    syncStatus = .idle
                    syncMessage = ""
                }
                
            } catch {
                await MainActor.run {
                    syncStatus = .error
                    syncMessage = "Error: \(error.localizedDescription)"
                    isSyncing = false
                }
            }
        }
    }
    
    private func testSearch() {
        isSyncing = true
        syncStatus = .syncing
        syncMessage = "Testing search..."
        
        Task {
            do {
                // Test user search
                let users = try await AlgoliaSearchService.shared.searchUsers(query: "test")
                
                // Test post search
                let posts = try await AlgoliaSearchService.shared.searchPosts(query: "faith")
                
                await MainActor.run {
                    syncStatus = .success
                    syncMessage = "Found \(users.count) users, \(posts.count) posts"
                    isSyncing = false
                }
                
                try await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    syncStatus = .idle
                    syncMessage = ""
                }
                
            } catch {
                await MainActor.run {
                    syncStatus = .error
                    syncMessage = "Search error: \(error.localizedDescription)"
                    isSyncing = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AlgoliaSyncDebugView()
}

// MARK: - Usage Instructions

/*
 📝 HOW TO USE THIS DEBUG VIEW:
 
 1️⃣ ADD TO YOUR APP:
 ───────────────────
 Add this view to your settings or debug menu:
 
 // In your SettingsView or similar
 NavigationLink("Algolia Sync (Admin)") {
     AlgoliaSyncDebugView()
 }
 
 
 2️⃣ INITIAL SETUP:
 ─────────────────
 a) First, make sure your Write API Key is configured in AlgoliaConfig.swift
 b) Open this view in your app
 c) Tap "Sync All Data" to populate Algolia with your existing Firestore data
 d) Wait for success message
 
 
 3️⃣ TESTING:
 ───────────
 - Tap "Test User Sync" to create a test user and verify it syncs
 - Tap "Test Post Sync" to create a test post and verify it syncs
 - Tap "Test Search" to verify search is working with synced data
 
 
 4️⃣ MAINTENANCE:
 ───────────────
 Use the individual sync buttons if you need to:
 - Re-sync all users after bulk changes
 - Re-sync all posts after bulk changes
 - Recover from sync issues
 
 
 ⚠️ IMPORTANT:
 ────────────
 - This view is for development/testing only
 - Remove or hide it before releasing to production
 - Consider adding authentication check (admin only)
 - The "Sync All Data" button can be expensive if you have lots of data
 */
