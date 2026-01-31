//
//  SearchKeywordsGenerator.swift
//  AMENAPP
//
//  Created by Steph on 1/29/26.
//

import Foundation
import SwiftUI
import FirebaseFirestore

/// Helper to generate and update search keywords for users and groups
struct SearchKeywordsGenerator {
    
    // MARK: - Generate Keywords
    
    /// Generate search keywords from text (name, username, etc.)
    static func generateKeywords(from text: String) -> [String] {
        var keywords: [String] = []
        let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add full text
        keywords.append(lowercased)
        
        // Add individual words
        let words = lowercased.components(separatedBy: .whitespacesAndNewlines)
        keywords.append(contentsOf: words.filter { !$0.isEmpty })
        
        // Add prefixes for autocomplete (1 to 10 characters)
        for i in 1...min(lowercased.count, 10) {
            let prefix = String(lowercased.prefix(i))
            keywords.append(prefix)
        }
        
        // Remove duplicates and empty strings
        return Array(Set(keywords)).filter { !$0.isEmpty }
    }
    
    /// Generate keywords for a user
    static func generateUserKeywords(displayName: String, username: String, bio: String? = nil) -> [String] {
        var allKeywords: [String] = []
        
        // From display name
        allKeywords.append(contentsOf: generateKeywords(from: displayName))
        
        // From username
        allKeywords.append(contentsOf: generateKeywords(from: username))
        
        // From bio (if provided)
        if let bio = bio {
            let bioWords = bio.lowercased().components(separatedBy: .whitespacesAndNewlines)
            allKeywords.append(contentsOf: bioWords.filter { $0.count > 2 }) // Only words > 2 chars
        }
        
        return Array(Set(allKeywords)).sorted()
    }
    
    /// Generate keywords for a group
    static func generateGroupKeywords(name: String, description: String? = nil, tags: [String] = []) -> [String] {
        var allKeywords: [String] = []
        
        // From name
        allKeywords.append(contentsOf: generateKeywords(from: name))
        
        // From description
        if let description = description {
            let words = description.lowercased().components(separatedBy: .whitespacesAndNewlines)
            allKeywords.append(contentsOf: words.filter { $0.count > 2 })
        }
        
        // From tags
        for tag in tags {
            allKeywords.append(contentsOf: generateKeywords(from: tag))
        }
        
        return Array(Set(allKeywords)).sorted()
    }
    
    // MARK: - Batch Update Existing Data
    
    /// Update all existing users with search keywords (run once)
    @MainActor
    static func updateAllUsersWithKeywords() async throws {
        let db = Firestore.firestore()
        
        print("🔄 Starting batch update of user search keywords...")
        
        let snapshot = try await db.collection("users").getDocuments()
        
        var updateCount = 0
        var errorCount = 0
        
        for document in snapshot.documents {
            do {
                let data = document.data()
                
                guard let displayName = data["displayName"] as? String,
                      let username = data["username"] as? String else {
                    print("⚠️ Skipping user \(document.documentID) - missing required fields")
                    continue
                }
                
                let bio = data["bio"] as? String
                let keywords = generateUserKeywords(
                    displayName: displayName,
                    username: username,
                    bio: bio
                )
                
                try await document.reference.updateData([
                    "searchKeywords": keywords
                ])
                
                updateCount += 1
                print("✅ Updated user: @\(username) (\(keywords.count) keywords)")
                
                // Add small delay to avoid rate limiting
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                
            } catch {
                errorCount += 1
                print("❌ Error updating user \(document.documentID): \(error)")
            }
        }
        
        print("✅ Batch update complete!")
        print("   - Successfully updated: \(updateCount) users")
        print("   - Errors: \(errorCount)")
    }
    
    /// Update all existing groups with search keywords (run once)
    @MainActor
    static func updateAllGroupsWithKeywords() async throws {
        let db = Firestore.firestore()
        
        print("🔄 Starting batch update of group search keywords...")
        
        let snapshot = try await db.collection("groups").getDocuments()
        
        var updateCount = 0
        var errorCount = 0
        
        for document in snapshot.documents {
            do {
                let data = document.data()
                
                guard let name = data["name"] as? String else {
                    print("⚠️ Skipping group \(document.documentID) - missing name")
                    continue
                }
                
                let description = data["description"] as? String
                let tags = data["tags"] as? [String] ?? []
                
                let keywords = generateGroupKeywords(
                    name: name,
                    description: description,
                    tags: tags
                )
                
                try await document.reference.updateData([
                    "searchKeywords": keywords
                ])
                
                updateCount += 1
                print("✅ Updated group: \(name) (\(keywords.count) keywords)")
                
                // Add small delay to avoid rate limiting
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                
            } catch {
                errorCount += 1
                print("❌ Error updating group \(document.documentID): \(error)")
            }
        }
        
        print("✅ Batch update complete!")
        print("   - Successfully updated: \(updateCount) groups")
        print("   - Errors: \(errorCount)")
    }
    
    // MARK: - Create Firestore Indexes
    
    /// Print the Firestore indexes needed
    static func printRequiredIndexes() {
        print("""
        
        📊 Required Firestore Indexes:
        
        1. Collection: users
           Fields:
           - searchKeywords (Array-contains)
           - createdAt (Descending)
        
        2. Collection: groups
           Fields:
           - searchKeywords (Array-contains)
           - memberCount (Descending)
        
        3. Collection: savedSearches
           Fields:
           - userId (Ascending)
           - createdAt (Descending)
        
        4. Collection: searchAlerts
           Fields:
           - userId (Ascending)
           - createdAt (Descending)
           - isRead (Ascending)
        
        To create these indexes:
        1. Go to Firebase Console → Firestore → Indexes
        2. Click "Create Index"
        3. Add the fields as specified above
        4. Wait for indexes to build (may take a few minutes)
        
        Or use the Firebase CLI:
        firebase deploy --only firestore:indexes
        
        """)
    }
}

// MARK: - Helper View to Run Batch Updates

struct SearchKeywordsMigrationView: View {
    @State private var isUpdatingUsers = false
    @State private var isUpdatingGroups = false
    @State private var showingResults = false
    @State private var resultMessage = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("This view helps you add search keywords to existing users and groups for autocomplete functionality.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
                
                Section {
                    Button {
                        updateUsers()
                    } label: {
                        HStack {
                            if isUpdatingUsers {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Update All Users")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                        }
                    }
                    .disabled(isUpdatingUsers || isUpdatingGroups)
                    
                    Button {
                        updateGroups()
                    } label: {
                        HStack {
                            if isUpdatingGroups {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Update All Groups")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                        }
                    }
                    .disabled(isUpdatingUsers || isUpdatingGroups)
                } header: {
                    Text("Batch Updates")
                } footer: {
                    Text("This will add searchKeywords field to all existing documents. Run once after implementing the search features.")
                        .font(.custom("OpenSans-Regular", size: 12))
                }
                
                Section {
                    Button {
                        SearchKeywordsGenerator.printRequiredIndexes()
                        resultMessage = "Check console for required Firestore indexes"
                        showingResults = true
                    } label: {
                        Text("Show Required Indexes")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                    }
                } header: {
                    Text("Firestore Indexes")
                }
            }
            .navigationTitle("Search Keywords Setup")
            .alert("Setup Result", isPresented: $showingResults) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resultMessage)
            }
        }
    }
    
    private func updateUsers() {
        isUpdatingUsers = true
        
        Task {
            do {
                try await SearchKeywordsGenerator.updateAllUsersWithKeywords()
                
                await MainActor.run {
                    resultMessage = "Successfully updated all users with search keywords!"
                    showingResults = true
                    isUpdatingUsers = false
                }
            } catch {
                await MainActor.run {
                    resultMessage = "Error: \(error.localizedDescription)"
                    showingResults = true
                    isUpdatingUsers = false
                }
            }
        }
    }
    
    private func updateGroups() {
        isUpdatingGroups = true
        
        Task {
            do {
                try await SearchKeywordsGenerator.updateAllGroupsWithKeywords()
                
                await MainActor.run {
                    resultMessage = "Successfully updated all groups with search keywords!"
                    showingResults = true
                    isUpdatingGroups = false
                }
            } catch {
                await MainActor.run {
                    resultMessage = "Error: \(error.localizedDescription)"
                    showingResults = true
                    isUpdatingGroups = false
                }
            }
        }
    }
}

#Preview {
    SearchKeywordsMigrationView()
}
