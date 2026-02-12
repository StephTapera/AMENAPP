//
//  AlgoliaSearchService.swift
//  AMENAPP
//
//  Created by Steph on 1/28/26.
//
//  Production-ready Algolia search service for instant, typo-tolerant search
//

import Foundation
import Combine
import Search

@MainActor
class AlgoliaSearchService: ObservableObject {
    static let shared = AlgoliaSearchService()
    
    @Published var isSearching = false
    @Published var error: String?
    
    private var client: SearchClient?
    private var usersIndexName = "users"
    private var postsIndexName = "posts"
    
    private init() {
        setupAlgoliaClient()
    }
    
    private func setupAlgoliaClient() {
        // Get credentials from AlgoliaConfig
        let appID = AlgoliaConfig.applicationID
        let apiKey = AlgoliaConfig.searchAPIKey
        
        // Validate credentials
        guard !appID.isEmpty && appID != "YOUR_APP_ID",
              !apiKey.isEmpty && apiKey != "YOUR_SEARCH_KEY" else {
            print("❌ Algolia credentials not configured in AlgoliaConfig.swift")
            return
        }
        
        // Initialize client
        do {
            client = try SearchClient(appID: appID, apiKey: apiKey)
            print("✅ Algolia client initialized successfully")
        } catch {
            print("❌ Failed to initialize Algolia client: \(error)")
            return
        }
        
        print("✅ Algolia client initialized successfully")
        print("   App ID: \(appID.prefix(8))...")
        print("   Users Index: \(usersIndexName)")
        print("   Posts Index: \(postsIndexName)")
    }
    
    // MARK: - Search Users
    
    /// Get autocomplete suggestions for users (fast, limited results)
    func getUserSuggestions(query: String, limit: Int = 5) async throws -> [AlgoliaUserSuggestion] {
        guard !query.isEmpty else { return [] }
        
        guard let client = client else {
            throw NSError(
                domain: "AlgoliaSearchService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Algolia not configured"]
            )
        }
        
        do {
            // Build search request with minimal attributes for speed
            let searchForHits = SearchForHits(
                query: query,
                attributesToRetrieve: [
                    "displayName",
                    "username",
                    "profileImageURL",
                    "followersCount"
                ],
                hitsPerPage: limit,
                indexName: usersIndexName,
                type: .default
            )
            
            // Wrap in SearchQuery enum
            let searchQuery = SearchQuery.searchForHits(searchForHits)
            
            // Perform search
            let responses: [SearchResponse<Hit>] = try await client.searchForHitsWithResponse(
                searchMethodParams: SearchMethodParams(requests: [searchQuery])
            )
            
            // Parse results
            guard let searchResponse = responses.first else {
                return []
            }
            
            let suggestions = searchResponse.hits.compactMap { hit -> AlgoliaUserSuggestion? in
                guard let displayName = hit.additionalProperties["displayName"] as? String,
                      let username = hit.additionalProperties["username"] as? String else {
                    return nil
                }
                
                return AlgoliaUserSuggestion(
                    id: hit.objectID,
                    displayName: displayName,
                    username: username,
                    profileImageURL: hit.additionalProperties["profileImageURL"] as? String,
                    followersCount: hit.additionalProperties["followersCount"] as? Int ?? 0
                )
            }
            
            return suggestions
            
        } catch {
            print("❌ Algolia suggestions error: \(error)")
            throw error
        }
    }
    
    /// Search users with Algolia (typo-tolerant, instant results)
    func searchUsers(query: String, limit: Int = 50) async throws -> [AlgoliaUser] {
        guard !query.isEmpty else { return [] }
        
        guard let client = client else {
            throw NSError(
                domain: "AlgoliaSearchService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Algolia not configured"]
            )
        }
        
        isSearching = true
        defer { isSearching = false }
        
        do {
            // Build search request using SearchForHits
            let searchForHits = SearchForHits(
                query: query,
                attributesToRetrieve: [
                    "displayName",
                    "username",
                    "bio",
                    "followersCount",
                    "followingCount",
                    "profileImageURL",
                    "isVerified"
                ],
                hitsPerPage: limit,
                indexName: usersIndexName,
                type: .default
            )
            
            // Wrap in SearchQuery enum
            let searchQuery = SearchQuery.searchForHits(searchForHits)
            
            // Perform search
            let responses: [SearchResponse<Hit>] = try await client.searchForHitsWithResponse(
                searchMethodParams: SearchMethodParams(requests: [searchQuery])
            )
            
            // Parse results
            guard let searchResponse = responses.first else {
                return []
            }
            
            let users = searchResponse.hits.compactMap { hit -> AlgoliaUser? in
                guard let displayName = hit.additionalProperties["displayName"] as? String,
                      let username = hit.additionalProperties["username"] as? String else {
                    return nil
                }
                
                return AlgoliaUser(
                    objectID: hit.objectID,
                    displayName: displayName,
                    username: username,
                    bio: hit.additionalProperties["bio"] as? String,
                    followersCount: hit.additionalProperties["followersCount"] as? Int,
                    followingCount: hit.additionalProperties["followingCount"] as? Int,
                    profileImageURL: hit.additionalProperties["profileImageURL"] as? String,
                    isVerified: hit.additionalProperties["isVerified"] as? Bool ?? false
                )
            }
            
            print("✅ Algolia found \(users.count) users for '\(query)'")
            return users
            
        } catch {
            print("❌ Algolia search error: \(error)")
            throw error
        }
    }
    
    // MARK: - Search Posts
    
    /// Search posts with Algolia
    func searchPosts(query: String, category: String? = nil, limit: Int = 50) async throws -> [AlgoliaPost] {
        guard !query.isEmpty else { return [] }
        
        guard let client = client else {
            throw NSError(
                domain: "AlgoliaSearchService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Algolia not configured"]
            )
        }
        
        isSearching = true
        defer { isSearching = false }
        
        do {
            // Build search request using SearchForHits
            let searchForHits = SearchForHits(
                query: query,
                filters: category.map { "category:\($0)" },
                attributesToRetrieve: [
                    "content",
                    "authorName",
                    "category",
                    "amenCount",
                    "commentCount",
                    "createdAt",
                    "mediaURLs",
                    "likesCount"
                ],
                hitsPerPage: limit,
                indexName: postsIndexName,
                type: .default
            )
            
            // Wrap in SearchQuery enum
            let searchQuery = SearchQuery.searchForHits(searchForHits)
            
            // Perform search
            let responses: [SearchResponse<Hit>] = try await client.searchForHitsWithResponse(
                searchMethodParams: SearchMethodParams(requests: [searchQuery])
            )
            
            // Parse results
            guard let searchResponse = responses.first else {
                return []
            }
            
            let posts = searchResponse.hits.compactMap { hit -> AlgoliaPost? in
                guard let content = hit.additionalProperties["content"] as? String,
                      let authorName = hit.additionalProperties["authorName"] as? String,
                      let categoryValue = hit.additionalProperties["category"] as? String else {
                    return nil
                }
                
                return AlgoliaPost(
                    objectID: hit.objectID,
                    content: content,
                    authorName: authorName,
                    category: categoryValue,
                    amenCount: hit.additionalProperties["amenCount"] as? Int,
                    commentCount: hit.additionalProperties["commentCount"] as? Int,
                    createdAt: hit.additionalProperties["createdAt"] as? TimeInterval,
                    mediaURLs: hit.additionalProperties["mediaURLs"] as? [String] ?? [],
                    likesCount: hit.additionalProperties["likesCount"] as? Int ?? 0
                )
            }
            
            print("✅ Algolia found \(posts.count) posts for '\(query)'")
            return posts
            
        } catch {
            print("❌ Algolia search error: \(error)")
            throw error
        }
    }
}

// MARK: - Algolia Models

/// Lightweight user suggestion for autocomplete
struct AlgoliaUserSuggestion: Codable, Identifiable {
    let id: String
    let displayName: String
    let username: String
    let profileImageURL: String?
    let followersCount: Int
    
    init(id: String, displayName: String, username: String, profileImageURL: String?, followersCount: Int) {
        self.id = id
        self.displayName = displayName
        self.username = username
        self.profileImageURL = profileImageURL
        self.followersCount = followersCount
    }
    
    init?(json: [String: Any]) {
        guard let id = json["objectID"] as? String,
              let displayName = json["displayName"] as? String,
              let username = json["username"] as? String else {
            return nil
        }
        
        self.id = id
        self.displayName = displayName
        self.username = username
        self.profileImageURL = json["profileImageURL"] as? String
        self.followersCount = json["followersCount"] as? Int ?? 0
    }
}

struct AlgoliaUser: Codable {
    let objectID: String
    let displayName: String
    let username: String
    let bio: String?
    let followersCount: Int?
    let followingCount: Int?
    let profileImageURL: String?
    let isVerified: Bool
    
    /// Convert to AppSearchResult for compatibility with existing UI
    func toSearchResult() -> AppSearchResult {
        let followersText = "\(followersCount ?? 0) followers"
        let bioText = bio.map { " • \($0.prefix(50))" } ?? ""
        
        return AppSearchResult(
            firestoreId: objectID,
            title: displayName,
            subtitle: "@\(username)",
            metadata: followersText + bioText,
            type: .person,
            isVerified: isVerified
        )
    }
    
    /// Convert to FirebaseSearchUser for compatibility with user search UI
    func toFirebaseSearchUser() -> FirebaseSearchUser {
        FirebaseSearchUser(
            id: objectID,
            username: username,
            displayName: displayName,
            profileImageURL: profileImageURL,
            bio: bio,
            isVerified: isVerified
        )
    }
    
    /// Convert to UserModel for compatibility with existing views
    func toUserModel() -> UserModel {
        // Note: UserModel doesn't have isVerified field, so it's not included
        return UserModel(
            id: objectID,
            email: "", // Email is not available from Algolia search
            displayName: displayName,
            username: username,
            bio: bio,
            profileImageURL: profileImageURL,
            followersCount: followersCount ?? 0,
            followingCount: followingCount ?? 0
        )
    }
}

struct AlgoliaPost: Codable, Identifiable {
    let objectID: String
    let content: String
    let authorName: String
    let category: String
    let amenCount: Int?
    let commentCount: Int?
    let createdAt: TimeInterval?
    let mediaURLs: [String]
    let likesCount: Int
    
    var id: String { objectID }
    
    /// Convert to AppSearchResult for compatibility with existing UI
    func toSearchResult() -> AppSearchResult {
        let timeAgo = createdAt
            .map { Date(timeIntervalSince1970: $0) }
            .map { self.formatTimeAgo(from: $0) } ?? "Recent"
        
        let contentPreview = content.count > 80
            ? String(content.prefix(80)) + "..."
            : content
        
        return AppSearchResult(
            firestoreId: objectID,
            title: contentPreview,
            subtitle: "by \(authorName)",
            metadata: "\(timeAgo) • \(amenCount ?? 0) Amens • \(commentCount ?? 0) comments",
            type: .post,
            isVerified: false
        )
    }
    
    private func formatTimeAgo(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        
        if seconds < 60 {
            return "now"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        } else if seconds < 86400 {
            return "\(Int(seconds / 3600))h"
        } else if seconds < 604800 {
            return "\(Int(seconds / 86400))d"
        } else {
            return "\(Int(seconds / 604800))w"
        }
    }
}
