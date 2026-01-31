//
//  SavedSearchIntegrationExamples.swift
//  AMENAPP
//
//  Examples of how to integrate SavedSearchService into your views
//

import SwiftUI
import Foundation

// MARK: - Example 1: Add "Save Search" to Search View

struct SearchViewWithSaveExample: View {
    @State private var searchText = ""
    @State private var selectedCategory = "Prayer"
    @State private var showSaveAlert = false
    @State private var showSavedSearches = false
    
    var body: some View {
        VStack {
            // Search bar
            HStack {
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                
                // Save search button
                Button {
                    Task {
                        await saveCurrentSearch()
                    }
                } label: {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding()
            
            // Show saved searches button
            Button("Saved Searches") {
                showSavedSearches = true
            }
            
            // Search results...
        }
        .alert("Search Saved!", isPresented: $showSaveAlert) {
            Button("OK") { }
        } message: {
            Text("You'll be notified when new content matches '\(searchText)'")
        }
        .sheet(isPresented: $showSavedSearches) {
            SavedSearchesListView()
        }
    }
    
    private func saveCurrentSearch() async {
        guard !searchText.isEmpty else { return }
        
        do {
            try await SavedSearchService.shared.saveSearch(
                query: searchText,
                category: selectedCategory,
                notificationsEnabled: true
            )
            showSaveAlert = true
        } catch SavedSearchError.alreadySaved {
            print("Search already saved")
        } catch {
            print("Error saving search: \(error)")
        }
    }
}

// MARK: - Example 2: Saved Searches List View

struct SavedSearchesListView: View {
    @StateObject private var searchService: SavedSearchService = .shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if searchService.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if searchService.savedSearches.isEmpty {
                    ContentUnavailableView(
                        "No Saved Searches",
                        systemImage: "bookmark.slash",
                        description: Text("Save searches to get notified of new matching content")
                    )
                } else {
                    ForEach(searchService.savedSearches) { search in
                        SavedSearchRow(search: search)
                    }
                    .onDelete(perform: deleteSearches)
                }
            }
            .navigationTitle("Saved Searches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                try? await searchService.fetchSavedSearches()
                searchService.startListening()
            }
            .onDisappear {
                searchService.stopListening()
            }
        }
    }
    
    private func deleteSearches(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let search = searchService.savedSearches[index]
                if let id = search.id {
                    try? await searchService.deleteSavedSearch(id: id)
                }
            }
        }
    }
}

struct SavedSearchRow: View {
    typealias SavedSearch = AMENAPP.SavedSearch
    let search: SavedSearch
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(search.query)
                        .font(.custom("OpenSans-Bold", size: 16))
                    
                    if let category = search.category {
                        Text(category)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Notification toggle
                Toggle("", isOn: Binding(
                    get: { search.notificationsEnabled },
                    set: { newValue in
                        Task { @MainActor in
                            if let id = search.id {
                                // Only toggle if the current state is different from desired state
                                if search.notificationsEnabled != newValue {
                                    try? await SavedSearchService.shared.toggleNotifications(
                                        searchId: id
                                    )
                                }
                            }
                        }
                    }
                ))
                .labelsHidden()
            }
            
            // Trigger count (shows how many times this search has been checked)
            if search.triggerCount > 0 {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    
                    Text("Checked \(search.triggerCount) time\(search.triggerCount == 1 ? "" : "s")")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                    
                    if let lastTriggered = search.lastTriggered {
                        Text("• \(lastTriggered, style: .relative) ago")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Example 3: Check for Matches When Creating Content

// NOTE: These extensions are examples only. Uncomment and modify them when you have
// the actual service classes (PrayerRequestService, TestimonyService, OpenTableService)
// available in your project.

/*
// Example extension for PrayerRequestService
extension PrayerRequestService {
    
    func createPrayerRequestWithNotifications(
        title: String,
        description: String,
        userId: String,
        userName: String
    ) async throws -> String {
        // 1. Create the prayer request (existing code)
        let prayerRequest = PrayerRequest(
            userId: userId,
            title: title,
            description: description,
            category: "Prayer",
            createdAt: Date()
        )
        
        // 2. Save to Firestore
        let docRef = try await db.collection("prayerRequests").addDocument(data: [
            "userId": prayerRequest.userId,
            "title": prayerRequest.title,
            "description": prayerRequest.description,
            "category": prayerRequest.category,
            "createdAt": prayerRequest.createdAt
        ])
        
        let prayerId = docRef.documentID
        
        // 3. Check for saved search matches 🎯 NEW!
        let fullText = "\(title) \(description)"
        try? await SavedSearchService.shared.checkForMatches(
            content: fullText,
            category: "Prayer",
            contentId: prayerId,
            authorId: userId,
            authorName: userName
        )
        
        print("✅ Prayer request created and checked for matches")
        
        return prayerId
    }
}
*/

// MARK: - Example 4: Search Settings in Profile

struct ProfileNotificationSettingsView: View {
    @StateObject private var searchService: SavedSearchService = .shared
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        SavedSearchesListView()
                    } label: {
                        HStack {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(.blue)
                            
                            Text("Saved Searches")
                            
                            Spacer()
                            
                            if !searchService.savedSearches.isEmpty {
                                Text("\(searchService.savedSearches.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Search Notifications")
                }
                
                Section {
                    Text("Get notified when new content matches your saved searches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Notifications")
            .task {
                try? await searchService.fetchSavedSearches()
            }
        }
    }
}

// MARK: - Example 5: Compact Save Search Button

struct SaveSearchButtonCompact: View {
    let searchQuery: String
    let category: String
    @State private var isSaved = false
    @State private var showAlert = false
    
    var body: some View {
        Button {
            Task {
                await saveSearch()
            }
        } label: {
            Label(
                isSaved ? "Saved" : "Save Search",
                systemImage: isSaved ? "bookmark.fill" : "bookmark"
            )
            .foregroundStyle(isSaved ? .green : .blue)
            .font(.caption)
        }
        .disabled(isSaved)
        .alert("Search Saved", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text("You'll be notified when new \(category.lowercased()) content matches '\(searchQuery)'")
        }
    }
    
    private func saveSearch() async {
        guard !searchQuery.isEmpty else { return }
        
        do {
            try await SavedSearchService.shared.saveSearch(
                query: searchQuery,
                category: category
            )
            isSaved = true
            showAlert = true
        } catch {
            print("Error saving search: \(error)")
        }
    }
}

// MARK: - Example 6: Using in Testimony Creation

/*
// Example extension for TestimonyService
extension TestimonyService {
    
    func createTestimonyWithNotifications(
        title: String,
        content: String,
        userId: String,
        userName: String
    ) async throws {
        // Create testimony (existing code)
        let testimony = Testimony(
            userId: userId,
            title: title,
            content: content,
            createdAt: Date()
        )
        
        let docRef = try await db.collection("testimonies").addDocument(data: [
            "userId": testimony.userId,
            "title": testimony.title,
            "content": testimony.content,
            "createdAt": testimony.createdAt
        ])
        
        // Check for saved search matches
        let fullText = "\(title) \(content)"
        try? await SavedSearchService.shared.checkForMatches(
            content: fullText,
            category: "Testimony",
            contentId: docRef.documentID,
            authorId: userId,
            authorName: userName
        )
        
        print("✅ Testimony created and checked for matches")
    }
}
*/

// MARK: - Example 7: Using in OpenTable Posts

/*
// Example extension for OpenTableService
extension OpenTableService {
    
    func createPostWithNotifications(
        title: String,
        content: String,
        userId: String,
        userName: String
    ) async throws {
        // Create post
        let post = OpenTablePost(
            userId: userId,
            title: title,
            content: content,
            createdAt: Date()
        )
        
        let docRef = try await db.collection("openTablePosts").addDocument(data: [
            "userId": post.userId,
            "title": post.title,
            "content": post.content,
            "createdAt": post.createdAt
        ])
        
        // Check for saved search matches
        let fullText = "\(title) \(content)"
        try? await SavedSearchService.shared.checkForMatches(
            content: fullText,
            category: "OpenTable",
            contentId: docRef.documentID,
            authorId: userId,
            authorName: userName
        )
        
        print("✅ OpenTable post created and checked for matches")
    }
}
*/

// MARK: - Example 8: Batch Check (for existing content migration)

// NOTE: This example is commented out because SavedSearchService doesn't currently have
// a checkForMatches() method. You would need to add this functionality to the service
// if you want to automatically check new content against saved searches.

/*
extension SavedSearchService {
    
    /// Check all existing content against saved searches (run once on app launch)
    func migrateExistingContent() async throws {
        print("🔄 Migrating existing content to check saved searches...")
        
        // To implement this, you would need to:
        // 1. Add a checkForMatches() method to SavedSearchService
        // 2. Make the db property accessible or add a helper method
        // 3. Implement the matching logic
        
        // Example implementation would look like:
        // - Fetch all saved searches for all users
        // - Iterate through recent content (prayer requests, testimonies, etc.)
        // - Check if content matches any saved search queries
        // - Create alerts for matches
        
        print("✅ Migration complete")
    }
}
*/

// MARK: - Usage in App

/*
 
 HOW TO INTEGRATE:
 
 1. In your SearchView:
    - Add SaveSearchButtonCompact wherever you show search results
    - Add "Saved Searches" button to open SavedSearchesListView
 
 2. In your content creation services:
    - Currently, SavedSearchService doesn't have checkForMatches() method
    - You can manually trigger checks using checkForNewResults()
    - Consider implementing a matching system if needed
 
 3. In your ProfileView:
    - Add link to ProfileNotificationSettingsView
    - Show saved search count
 
 4. Manual Check Example:
    // Manually trigger a check for a saved search
    if let savedSearch = SavedSearchService.shared.savedSearches.first {
        await SavedSearchService.shared.checkForNewResults(savedSearch: savedSearch)
    }
 
 */

