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

// MARK: - AnyCodable → [String: Any] helper
// AnyCodable's inner `.value` lives in the `Core` module which cannot be imported directly.
// We use a JSON round-trip to convert additionalProperties to a plain [String: Any] dictionary.
private func decodeAdditionalProperties<T: Encodable>(_ props: [String: T]?) -> [String: Any] {
    guard let props else { return [:] }
    guard let data = try? JSONEncoder().encode(props),
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return dict
}

@MainActor
class AlgoliaSearchService: ObservableObject {
    static let shared = AlgoliaSearchService()
    
    @Published var isSearching = false
    @Published var error: String?
    
    private var client: SearchClient?
    private var usersIndexName = "users"
    private var postsIndexName = "posts"

    // In-flight task tracking — cancels previous search before starting a new one
    // to prevent noReachableHosts errors from concurrent cancelled requests.
    private var activeSearchTask: Task<Void, Never>?
    
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
            dlog("❌ Algolia credentials not configured in AlgoliaConfig.swift")
            return
        }
        
        // Initialize client
        do {
            client = try SearchClient(appID: appID, apiKey: apiKey)
            dlog("✅ Algolia client initialized successfully")
        } catch {
            dlog("❌ Failed to initialize Algolia client: \(error)")
            return
        }
        
        dlog("✅ Algolia client initialized successfully")
        dlog("   App ID: \(appID.prefix(8))...")
        dlog("   Users Index: \(usersIndexName)")
        dlog("   Posts Index: \(postsIndexName)")
    }
    
    // MARK: - Search Users
    
    /// Get autocomplete suggestions for users (fast, limited results)
    func getUserSuggestions(query: String, limit: Int = 5) async throws -> [AlgoliaUserSuggestion] {
        guard !query.isEmpty else { return [] }

        // Bail out immediately if a newer search has already cancelled this task.
        try Task.checkCancellation()

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
                let props = decodeAdditionalProperties(hit.additionalProperties)
                guard let displayName = props["displayName"] as? String,
                      let username = props["username"] as? String else {
                    return nil
                }
                
                return AlgoliaUserSuggestion(
                    id: hit.objectID,
                    displayName: displayName,
                    username: username,
                    profileImageURL: props["profileImageURL"] as? String,
                    followersCount: props["followersCount"] as? Int ?? 0
                )
            }
            
            return suggestions
            
        } catch is CancellationError {
            // Task was cancelled by a newer keystroke — suppress noisy noReachableHosts logs.
            throw CancellationError()
        } catch let nsError as NSError where nsError.code == NSURLErrorCancelled {
            // URLSession -999 cancel — same cause, suppress.
            throw CancellationError()
        } catch {
            dlog("❌ Algolia suggestions error: \(error)")
            throw error
        }
    }
    
    /// Search users with Algolia (typo-tolerant, instant results).
    /// Call sites should cancel the previous task before creating a new one (see activeSearchTask).
    func searchUsers(query: String, limit: Int = 50) async throws -> [AlgoliaUser] {
        guard !query.isEmpty else { return [] }

        // Bail out immediately if a newer search has already cancelled this task.
        try Task.checkCancellation()

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
                let props = decodeAdditionalProperties(hit.additionalProperties)
                guard let displayName = props["displayName"] as? String,
                      let username = props["username"] as? String else {
                    return nil
                }
                
                return AlgoliaUser(
                    objectID: hit.objectID,
                    displayName: displayName,
                    username: username,
                    bio: props["bio"] as? String,
                    followersCount: props["followersCount"] as? Int,
                    followingCount: props["followingCount"] as? Int,
                    profileImageURL: props["profileImageURL"] as? String,
                    isVerified: props["isVerified"] as? Bool ?? false
                )
            }
            
            dlog("✅ Algolia found \(users.count) users for '\(query)'")
            return users
            
        } catch {
            dlog("❌ Algolia search error: \(error)")
            throw error
        }
    }
    
    // MARK: - Search Posts
    
    /// Search posts with Algolia
    func searchPosts(query: String, category: String? = nil, limit: Int = 50) async throws -> [AlgoliaPost] {
        guard !query.isEmpty else { return [] }

        // Bail out immediately if a newer search has already cancelled this task.
        try Task.checkCancellation()

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
            // Build safety + privacy filter.
            // - authorIsPrivate:false — never expose private-account posts
            // - isRemoved:false      — hide posts deleted/removed by moderation
            // - isFlagged:false      — hide posts currently under review
            // These fields must be present and kept in-sync in the Algolia index
            // (set by the AlgoliaSyncService when posts are created/moderated).
            let safetyFilters = "authorIsPrivate:false AND isRemoved:false AND isFlagged:false"
            
            // Combine category filter with safety filters
            var combinedFilters: String?
            if let categoryFilter = category.map({ "category:\($0)" }) {
                combinedFilters = "\(categoryFilter) AND \(safetyFilters)"
            } else {
                combinedFilters = safetyFilters
            }
            
            // Build search request using SearchForHits
            let searchForHits = SearchForHits(
                query: query,
                filters: combinedFilters,
                attributesToRetrieve: [
                    "content",
                    "authorName",
                    "authorId",
                    "category",
                    "amenCount",
                    "commentCount",
                    "createdAt",
                    "mediaURLs",
                    "likesCount",
                    "authorIsPrivate"  // P0-8: Include privacy field
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
                let props = decodeAdditionalProperties(hit.additionalProperties)
                guard let content = props["content"] as? String,
                      let authorName = props["authorName"] as? String,
                      let categoryValue = props["category"] as? String else {
                    return nil
                }
                
                return AlgoliaPost(
                    objectID: hit.objectID,
                    content: content,
                    authorName: authorName,
                    authorId: props["authorId"] as? String,  // P0-8
                    category: categoryValue,
                    authorIsPrivate: props["authorIsPrivate"] as? Bool,  // P0-8
                    amenCount: props["amenCount"] as? Int,
                    commentCount: props["commentCount"] as? Int,
                    createdAt: props["createdAt"] as? TimeInterval,
                    mediaURLs: props["mediaURLs"] as? [String] ?? [],
                    likesCount: props["likesCount"] as? Int ?? 0
                )
            }
            
            dlog("✅ Algolia found \(posts.count) posts for '\(query)'")
            return posts
            
        } catch {
            dlog("❌ Algolia search error: \(error)")
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
    let authorId: String?  // ✅ P0-8: Added for privacy filtering
    let category: String
    let authorIsPrivate: Bool?  // ✅ P0-8: Privacy flag
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
