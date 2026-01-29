//
//  HomeViewModel.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedCategory: String = "#OPENTABLE"
    @Published var posts: [Post] = []
    @Published var trendingTopics: [TrendingTopic] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Properties
    let categories = ["Testimonies", "#OPENTABLE", "Prayer"]
    
    // MARK: - Initialization
    init() {
        loadInitialData()
    }
    
    // MARK: - Public Methods
    func loadInitialData() {
        // For now, load mock data
        // Later, replace with API calls
        posts = PostsManager.shared.allPosts
        trendingTopics = TrendingTopic.mockTopics
    }
    
    func selectCategory(_ category: String) {
        selectedCategory = category
        Task {
            await loadPostsForCategory(category)
        }
    }
    
    func refreshPosts() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Simulate network delay
            try await Task.sleep(for: .seconds(1))
            
            // TODO: Replace with actual API call
            // posts = try await PostService.shared.fetchPosts(category: selectedCategory)
            
            // Convert category string to PostCategory enum
            let categoryEnum: Post.PostCategory
            switch selectedCategory {
            case "#OPENTABLE":
                categoryEnum = .openTable
            case "Testimonies":
                categoryEnum = .testimonies
            case "Prayer":
                categoryEnum = .prayer
            default:
                categoryEnum = .openTable
            }
            
            posts = PostsManager.shared.getPosts(for: categoryEnum)
            
        } catch {
            errorMessage = "Failed to load posts: \(error.localizedDescription)"
        }
    
        isLoading = false
    }
    
    func likePost(_ post: Post) {
        // TODO: Implement API call
        if let  vbnmnbvcindex = posts.firstIndex(where: { $0.id == post.id }) {
            // Update locally (will be replaced with proper model update)
            print("Liked post: \(post.id)")
        }
    }
    
    func sharePost(_ post: Post) {
        // TODO: Implement sharing functionality
        print("Share post: \(post.id)")
    }
    
    func reportPost(_ post: Post) {
        // TODO: Implement reporting functionality
        print("Report post: \(post.id)")
    }
    
    // MARK: - Private Methods
    private func loadPostsForCategory(_ category: String) async {
        await refreshPosts()
    }
}
