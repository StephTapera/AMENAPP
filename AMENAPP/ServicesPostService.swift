//
//  PostService.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import Foundation

/// Service responsible for all post-related API calls
class PostService {
    static let shared = PostService()
    
    private let baseURL = "https://api.amenapp.com/v1" // TODO: Replace with actual API URL
    
    private init() {}
    
    // MARK: - Fetch Posts
    
    /// Fetch posts for a specific category
    func fetchPosts(category: String, limit: Int = 20) async throws -> [LegacyPost] {
        // TODO: Implement actual API call
        /*
        let url = URL(string: "\(baseURL)/posts?category=\(category)&limit=\(limit)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let posts = try JSONDecoder().decode([LegacyPost].self, from: data)
        return posts
        */
        
        // For now, return mock data
        try await Task.sleep(for: .seconds(1))
        return LegacyPost.mockPosts.filter { $0.category == category }
    }
    
    /// Fetch all posts
    func fetchAllPosts(limit: Int = 50) async throws -> [LegacyPost] {
        // TODO: Implement actual API call
        try await Task.sleep(for: .seconds(1))
        return LegacyPost.mockPosts
    }
    
    // MARK: - Create Post
    
    /// Create a new post
    func createPost(content: String, category: String) async throws -> LegacyPost {
        // TODO: Implement actual API call
        /*
        let url = URL(string: "\(baseURL)/posts")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["content": content, "category": category]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let post = try JSONDecoder().decode(LegacyPost.self, from: data)
        return post
        */
        
        // For now, return a mock post
        try await Task.sleep(for: .seconds(0.5))
        return LegacyPost(
            authorId: "current_user_id",
            authorName: "Current User",
            authorUsername: "@currentuser",
            content: content,
            category: category
        )
    }
    
    // MARK: - Interactions
    
    /// Like or unlike a post
    func toggleLike(postId: String) async throws {
        // TODO: Implement actual API call
        /*
        let url = URL(string: "\(baseURL)/posts/\(postId)/like")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.invalidResponse
        }
        */
        
        try await Task.sleep(for: .seconds(0.3))
        print("Toggled like for post: \(postId)")
    }
    
    /// Report a post
    func reportPost(postId: String, reason: String) async throws {
        // TODO: Implement actual API call
        try await Task.sleep(for: .seconds(0.3))
        print("Reported post: \(postId) for reason: \(reason)")
    }
    
    /// Delete a post
    func deletePost(postId: String) async throws {
        // TODO: Implement actual API call
        try await Task.sleep(for: .seconds(0.3))
        print("Deleted post: \(postId)")
    }
}

// MARK: - Network Errors

enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingError
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError:
            return "Failed to decode response"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
