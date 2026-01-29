//
//  SearchService.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Service for searching users, communities, posts, and events
//

import Foundation
import FirebaseFirestore
import Combine
import SwiftUI

// MARK: - Search Result Model

struct AppSearchResult: Identifiable {
    let id = UUID()
    let firestoreId: String?  // Firebase document ID for the user/post/group
    let title: String
    let subtitle: String
    let metadata: String
    let type: ResultType
    let isVerified: Bool
    
    enum ResultType {
        case person
        case group
        case post
        case event
        
        var icon: String {
            switch self {
            case .person: return "person.circle.fill"
            case .group: return "person.3.fill"
            case .post: return "doc.text.fill"
            case .event: return "calendar.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .person: return .blue
            case .group: return .purple
            case .post: return .orange
            case .event: return .green
            }
        }
    }
}

// MARK: - Trending Item Model

struct TrendingItem: Identifiable {
    let id = UUID()
    let title: String
    let posts: String
    let trend: TrendDirection
    let category: String
    
    enum TrendDirection {
        case up
        case down
        case stable
        
        var icon: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .stable: return "minus"
            }
        }
        
        var color: Color {
            switch self {
            case .up: return .green
            case .down: return .red
            case .stable: return .gray
            }
        }
    }
}

@MainActor
class SearchService: ObservableObject {
    static let shared = SearchService()
    
    private let db = Firestore.firestore()
    private let firebaseManager = FirebaseManager.shared
    
    @Published var isSearching = false
    @Published var searchResults: [AppSearchResult] = []
    @Published var recentSearches: [String] = []
    @Published var error: String?
    
    private let maxRecentSearches = 10
    
    private init() {
        loadRecentSearches()
    }
    
    // MARK: - Main Search Function
    
    /// Search across all categories
    func search(query: String, filter: SearchViewTypes.SearchFilter = .all) async throws -> [AppSearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return []
        }
        
        print("🔍 Searching for: '\(query)' with filter: \(filter.rawValue)")
        
        isSearching = true
        defer { isSearching = false }
        
        var results: [AppSearchResult] = []
        
        switch filter {
        case .all:
            // Search all categories in parallel
            async let people = searchPeople(query: query)
            async let groups = searchGroups(query: query)
            async let posts = searchPosts(query: query)
            async let events = searchEvents(query: query)
            
            let (peopleResults, groupResults, postResults, eventResults) = try await (people, groups, posts, events)
            
            results = peopleResults + groupResults + postResults + eventResults
            
        case .people:
            results = try await searchPeople(query: query)
            
        case .groups:
            results = try await searchGroups(query: query)
            
        case .posts:
            results = try await searchPosts(query: query)
            
        case .events:
            results = try await searchEvents(query: query)
        }
        
        // Sort by relevance
        results = sortByRelevance(results, query: query)
        
        // Save to recent searches
        saveRecentSearch(query)
        
        await MainActor.run {
            self.searchResults = results
        }
        
        print("✅ Found \(results.count) results")
        
        return results
    }
    
    // MARK: - Search People/Users
    
    func searchPeople(query: String) async throws -> [AppSearchResult] {
        let lowercaseQuery = query.lowercased()
        print("🔍 Searching people with Algolia: '\(lowercaseQuery)'")
        
        do {
            // Use Algolia for search (typo-tolerant, instant results)
            let algoliaUsers = try await AlgoliaSearchService.shared.searchUsers(query: lowercaseQuery)
            let results = algoliaUsers.map { $0.toSearchResult() }
            
            print("✅ Found \(results.count) people via Algolia")
            return results
            
        } catch {
            print("⚠️ Algolia search failed, falling back to Firestore: \(error)")
            
            // Fallback to Firestore if Algolia fails
            return try await searchPeopleFirestore(query: lowercaseQuery)
        }
    }
    
    // MARK: - Firestore Fallback (kept for reliability)
    
    private func searchPeopleFirestore(query: String) async throws -> [AppSearchResult] {
        let lowercaseQuery = query.lowercased()
        print("🔍 Searching people with query: '\(lowercaseQuery)'")
        
        var results: [AppSearchResult] = []
        
        // STRATEGY 1: Try searching with lowercase fields (if they exist)
        do {
            let snapshot = try await db.collection(FirebaseManager.CollectionPath.users)
                .whereField("usernameLowercase", isGreaterThanOrEqualTo: lowercaseQuery)
                .whereField("usernameLowercase", isLessThanOrEqualTo: lowercaseQuery + "\u{f8ff}")
                .limit(to: 20)
                .getDocuments()
            
            print("✅ Found \(snapshot.documents.count) users by usernameLowercase")
            
            for document in snapshot.documents {
                if let result = parseUserDocument(document) {
                    results.append(result)
                }
            }
            
            // Also search by display name
            let nameSnapshot = try await db.collection(FirebaseManager.CollectionPath.users)
                .whereField("displayNameLowercase", isGreaterThanOrEqualTo: lowercaseQuery)
                .whereField("displayNameLowercase", isLessThanOrEqualTo: lowercaseQuery + "\u{f8ff}")
                .limit(to: 20)
                .getDocuments()
            
            print("✅ Found \(nameSnapshot.documents.count) users by displayNameLowercase")
            
            for document in nameSnapshot.documents {
                if let result = parseUserDocument(document) {
                    // Skip duplicates
                    if !results.contains(where: { $0.firestoreId == result.firestoreId }) {
                        results.append(result)
                    }
                }
            }
            
        } catch {
            print("⚠️ Lowercase field search failed (fields may not exist): \(error)")
            print("📝 Falling back to client-side filtering...")
            
            // STRATEGY 2: Fallback - Get all users and filter client-side (NOT IDEAL but works)
            // Only do this for development. In production, you MUST add lowercase fields.
            let allUsersSnapshot = try await db.collection(FirebaseManager.CollectionPath.users)
                .limit(to: 100)  // Limit to prevent huge downloads
                .getDocuments()
            
            print("📥 Downloaded \(allUsersSnapshot.documents.count) users for client-side search")
            
            for document in allUsersSnapshot.documents {
                let data = document.data()
                
                // Check if username or displayName contains the query
                let username = (data["username"] as? String ?? "").lowercased()
                let displayName = (data["displayName"] as? String ?? "").lowercased()
                
                if username.contains(lowercaseQuery) || displayName.contains(lowercaseQuery) {
                    if let result = parseUserDocument(document) {
                        results.append(result)
                    }
                }
            }
            
            print("✅ Client-side filter found \(results.count) matching users")
        }
        
        print("✅ Total people results: \(results.count)")
        return results
    }
    
    // Helper to parse user document into AppSearchResult
    private func parseUserDocument(_ document: QueryDocumentSnapshot) -> AppSearchResult? {
        let data = document.data()
        let userId = document.documentID
        
        guard let username = data["username"] as? String,
              let displayName = data["displayName"] as? String else {
            print("⚠️ Skipping user \(userId) - missing username or displayName")
            return nil
        }
        
        let bio = data["bio"] as? String
        let isVerified = data["isVerified"] as? Bool ?? false
        let followerCount = data["followersCount"] as? Int ?? 0
        
        return AppSearchResult(
            firestoreId: userId,
            title: displayName,
            subtitle: "@\(username)",
            metadata: "\(followerCount) followers" + (bio != nil && !bio!.isEmpty ? " • \(bio!.prefix(50))" : ""),
            type: .person,
            isVerified: isVerified
        )
    }
    
    // MARK: - Search Groups/Communities
    
    func searchGroups(query: String) async throws -> [AppSearchResult] {
        let lowercaseQuery = query.lowercased()
        
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.communities)
            .whereField("nameLowercase", isGreaterThanOrEqualTo: lowercaseQuery)
            .whereField("nameLowercase", isLessThanOrEqualTo: lowercaseQuery + "\u{f8ff}")
            .limit(to: 20)
            .getDocuments()
        
        var results: [AppSearchResult] = []
        
        for document in snapshot.documents {
            let data = document.data()
            
            guard let name = data["name"] as? String else {
                continue
            }
            
            let description = data["description"] as? String ?? ""
            let memberCount = data["memberCount"] as? Int ?? 0
            let isPrivate = data["isPrivate"] as? Bool ?? false
            let isVerified = data["isVerified"] as? Bool ?? false
            
            results.append(AppSearchResult(
                firestoreId: nil,  // Groups don't need user ID
                title: name,
                subtitle: isPrivate ? "🔒 Private Group" : "Public Group",
                metadata: "\(memberCount) members" + (!description.isEmpty ? " • \(description.prefix(50))" : ""),
                type: .group,
                isVerified: isVerified
            ))
        }
        
        return results
    }
    
    // MARK: - Search Posts
    
    func searchPosts(query: String) async throws -> [AppSearchResult] {
        let lowercaseQuery = query.lowercased()
        print("🔍 Searching posts with Algolia: '\(lowercaseQuery)'")
        
        do {
            // Use Algolia for search (typo-tolerant, instant results)
            let algoliaPosts = try await AlgoliaSearchService.shared.searchPosts(query: lowercaseQuery)
            let results = algoliaPosts.map { $0.toSearchResult() }
            
            print("✅ Found \(results.count) posts via Algolia")
            return results
            
        } catch {
            print("⚠️ Algolia search failed, falling back to Firestore: \(error)")
            
            // Fallback to Firestore if Algolia fails
            return try await searchPostsFirestore(query: lowercaseQuery)
        }
    }
    
    // MARK: - Firestore Posts Fallback
    
    private func searchPostsFirestore(query: String) async throws -> [AppSearchResult] {
        let lowercaseQuery = query.lowercased()
        
        // Note: Firestore doesn't support full-text search natively
        // For production, Algolia is recommended
        
        // For now, we'll search by hashtags and content prefix
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
            .whereField("contentLowercase", isGreaterThanOrEqualTo: lowercaseQuery)
            .whereField("contentLowercase", isLessThanOrEqualTo: lowercaseQuery + "\u{f8ff}")
            .limit(to: 20)
            .getDocuments()
        
        var results: [AppSearchResult] = []
        
        for document in snapshot.documents {
            let data = document.data()
            
            guard let content = data["content"] as? String,
                  let authorName = data["authorName"] as? String else {
                continue
            }
            
            let amenCount = data["amenCount"] as? Int ?? 0
            let commentCount = data["commentCount"] as? Int ?? 0
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            
            let timeAgo = SearchService.formatTimeAgo(from: createdAt)
            
            results.append(AppSearchResult(
                firestoreId: nil,  // Posts don't need this
                title: content.prefix(80) + (content.count > 80 ? "..." : ""),
                subtitle: "by \(authorName)",
                metadata: "\(timeAgo) • \(amenCount) Amens • \(commentCount) comments",
                type: .post,
                isVerified: false
            ))
        }
        
        // Also search by hashtags if query starts with #
        if query.hasPrefix("#") {
            let hashtag = String(query.dropFirst()).lowercased()
            
            let hashtagSnapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
                .whereField("hashtagsLowercase", arrayContains: hashtag)
                .limit(to: 20)
                .getDocuments()
            
            for document in hashtagSnapshot.documents {
                let data = document.data()
                
                guard let content = data["content"] as? String,
                      let authorName = data["authorName"] as? String else {
                    continue
                }
                
                // Skip duplicates
                if results.contains(where: { $0.title == content.prefix(80) + (content.count > 80 ? "..." : "") }) {
                    continue
                }
                
                let amenCount = data["amenCount"] as? Int ?? 0
                let commentCount = data["commentCount"] as? Int ?? 0
                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                
                let timeAgo = SearchService.formatTimeAgo(from: createdAt)
                
                results.append(AppSearchResult(
                    firestoreId: nil,
                    title: content.prefix(80) + (content.count > 80 ? "..." : ""),
                    subtitle: "by \(authorName)",
                    metadata: "\(timeAgo) • \(amenCount) Amens • \(commentCount) comments",
                    type: .post,
                    isVerified: false
                ))
            }
        }
        
        return results
    }
    
    // MARK: - Search Events
    
    func searchEvents(query: String) async throws -> [AppSearchResult] {
        let lowercaseQuery = query.lowercased()
        
        let snapshot = try await db.collection("events")
            .whereField("titleLowercase", isGreaterThanOrEqualTo: lowercaseQuery)
            .whereField("titleLowercase", isLessThanOrEqualTo: lowercaseQuery + "\u{f8ff}")
            .limit(to: 20)
            .getDocuments()
        
        var results: [AppSearchResult] = []
        
        for document in snapshot.documents {
            let data = document.data()
            
            guard let title = data["title"] as? String else {
                continue
            }
            
            let location = data["location"] as? String ?? "Online"
            let date = (data["date"] as? Timestamp)?.dateValue() ?? Date()
            let attendeeCount = data["attendeeCount"] as? Int ?? 0
            let isVerified = data["isVerified"] as? Bool ?? false
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            
            results.append(AppSearchResult(
                firestoreId: nil,
                title: title,
                subtitle: dateFormatter.string(from: date),
                metadata: "\(location) • \(attendeeCount) attending",
                type: .event,
                isVerified: isVerified
            ))
        }
        
        return results
    }
    
    // MARK: - Trending Topics
    
    func getTrendingTopics() async throws -> [TrendingItem] {
        // Query posts created in the last 7 days and aggregate hashtags
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
            .whereField("createdAt", isGreaterThan: Timestamp(date: sevenDaysAgo))
            .limit(to: 100)
            .getDocuments()
        
        var hashtagCounts: [String: Int] = [:]
        
        for document in snapshot.documents {
            if let hashtags = document.data()["hashtags"] as? [String] {
                for hashtag in hashtags {
                    hashtagCounts[hashtag, default: 0] += 1
                }
            }
        }
        
        // Sort by count and return top trending
        let trending = hashtagCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { (hashtag, count) in
                TrendingItem(
                    title: "#\(hashtag)",
                    posts: "\(count) posts",
                    trend: .up,
                    category: "Trending"
                )
            }
        
        return Array(trending)
    }
    
    // MARK: - Recent Searches
    
    func saveRecentSearch(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        // Remove if already exists
        recentSearches.removeAll { $0 == query }
        
        // Add to beginning
        recentSearches.insert(query, at: 0)
        
        // Limit to max
        if recentSearches.count > maxRecentSearches {
            recentSearches = Array(recentSearches.prefix(maxRecentSearches))
        }
        
        // Save to UserDefaults
        UserDefaults.standard.set(recentSearches, forKey: "recentSearches")
    }
    
    func loadRecentSearches() {
        if let saved = UserDefaults.standard.stringArray(forKey: "recentSearches") {
            recentSearches = saved
        }
    }
    
    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: "recentSearches")
    }
    
    // MARK: - Helper Methods
    
    private func sortByRelevance(_ results: [AppSearchResult], query: String) -> [AppSearchResult] {
        return results.sorted { result1, result2 in
            let score1 = relevanceScore(for: result1, query: query)
            let score2 = relevanceScore(for: result2, query: query)
            return score1 > score2
        }
    }
    
    private func relevanceScore(for result: AppSearchResult, query: String) -> Int {
        var score = 0
        let lowercaseQuery = query.lowercased()
        let lowercaseTitle = result.title.lowercased()
        let lowercaseSubtitle = result.subtitle.lowercased()
        
        // Exact match
        if lowercaseTitle == lowercaseQuery {
            score += 100
        }
        
        // Starts with query
        if lowercaseTitle.hasPrefix(lowercaseQuery) {
            score += 50
        }
        
        // Contains query
        if lowercaseTitle.contains(lowercaseQuery) {
            score += 25
        }
        
        // Subtitle matches
        if lowercaseSubtitle.contains(lowercaseQuery) {
            score += 10
        }
        
        // Verified users get bonus
        if result.isVerified {
            score += 5
        }
        
        return score
    }
    
    // Helper function to format time ago
    static func formatTimeAgo(from date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.minute, .hour, .day, .weekOfYear, .month, .year], from: date, to: now)
        
        if let year = components.year, year > 0 {
            return "\(year)y"
        }
        if let month = components.month, month > 0 {
            return "\(month)mo"
        }
        if let week = components.weekOfYear, week > 0 {
            return "\(week)w"
        }
        if let day = components.day, day > 0 {
            return "\(day)d"
        }
        if let hour = components.hour, hour > 0 {
            return "\(hour)h"
        }
        if let minute = components.minute, minute > 0 {
            return "\(minute)m"
        }
        return "now"
    }
}

// MARK: - Firestore Index Requirements

/*
 ⚠️ IMPORTANT: You need to create the following Firestore indexes:
 
 1. **Users Collection** - For searching people
    - Collection: users
    - Fields: usernameLowercase (Ascending), __name__ (Ascending)
    - Fields: displayNameLowercase (Ascending), __name__ (Ascending)
 
 2. **Communities Collection** - For searching groups
    - Collection: communities
    - Fields: nameLowercase (Ascending), __name__ (Ascending)
 
 3. **Posts Collection** - For searching posts
    - Collection: posts
    - Fields: contentLowercase (Ascending), __name__ (Ascending)
    - Fields: hashtagsLowercase (Array), createdAt (Descending)
    - Fields: createdAt (Descending), __name__ (Ascending)
 
 4. **Events Collection** - For searching events
    - Collection: events
    - Fields: titleLowercase (Ascending), __name__ (Ascending)
 
 ## How to Create Indexes:
 
 1. Run the app and perform a search
 2. Check Xcode console for Firestore error messages with index creation links
 3. Click the link to auto-create the index in Firebase Console
 
 OR
 
 Create them manually in Firebase Console:
 - Go to Firestore Database > Indexes
 - Click "Create Index"
 - Add the fields as specified above
 
 ## Better Search Solution (Production):
 
 For production apps, use **Algolia** for full-text search:
 - Install Firebase Extension for Algolia
 - Or use Algolia SDK directly
 - Much faster and more powerful than Firestore queries
 
 Example Algolia integration:
 
 ```swift
 import InstantSearchSwiftUI
 
 class AlgoliaSearchService {
     let client = SearchClient(appID: "YOUR_APP_ID", apiKey: "YOUR_API_KEY")
     
     func search(query: String) async -> [SearchResult] {
         let index = client.index(withName: "users")
         let response = try await index.search(query: query)
         // Process results
     }
 }
 ```
 
 ## Data Model Requirements:
 
 Make sure your Firestore documents include lowercase fields:
 
 - users: usernameLowercase, displayNameLowercase
 - communities: nameLowercase
 - posts: contentLowercase, hashtagsLowercase (array)
 - events: titleLowercase
 
 These should be set when creating/updating documents.
 */
