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
        isLoading = false
    }
    
    /// Toggle amen/lightbulb reaction on a post via the real-time interactions service.
    func likePost(_ post: Post) {
        guard let postId = post.firebaseId else { return }
        Task {
            do {
                try await PostInteractionsService.shared.toggleAmen(postId: postId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    /// Share a post by presenting the native share sheet via PostShareOptionsSheet.
    /// Callers are expected to present PostShareOptionsSheet(post:) — this method
    /// records the share signal so the feed algorithm can learn from it.
    func sharePost(_ post: Post) {
        guard let postId = post.firebaseId else { return }
        Task {
            await HeyFeedPreferencesService.shared.recordMoreLikeThis(
                postId: postId,
                authorId: post.authorId
            )
        }
    }
    
    /// File a report against a post using the existing ModerationService pipeline.
    func reportPost(_ post: Post) {
        guard let postId = post.firebaseId else { return }
        Task {
            do {
                try await ModerationService.shared.reportPost(
                    postId: postId,
                    postAuthorId: post.authorId,
                    reason: .inappropriateContent,
                    additionalDetails: nil
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Private Methods
    private func loadPostsForCategory(_ category: String) async {
        await refreshPosts()
    }
}
