//
//  PostInteractionsViewModel.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Unified view model for handling all post interactions
//

import SwiftUI
import Combine

@MainActor
class PostInteractionsViewModel: ObservableObject {
    // MARK: - Services
    private let commentService = CommentService.shared
    private let savedPostsService = SavedPostsService.shared
    private let repostService = RepostService.shared
    
    // MARK: - Published Properties
    
    // Comments
    @Published var comments: [CommentWithReplies] = []
    @Published var isLoadingComments = false
    
    // Saved Posts
    @Published var savedPostIds: Set<String> = []
    
    // Reposts
    @Published var repostedPostIds: Set<String> = []
    
    // UI State
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var isProcessing = false
    
    // MARK: - Cancellables
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // Bind saved posts
        savedPostsService.$savedPostIds
            .assign(to: &$savedPostIds)
        
        // Bind reposts
        repostService.$repostedPostIds
            .assign(to: &$repostedPostIds)
    }
    
    // MARK: - Comments
    
    /// Fetch comments for a post
    func fetchComments(for postId: String) async {
        isLoadingComments = true
        defer { isLoadingComments = false }
        
        do {
            let fetchedComments = try await commentService.fetchCommentsWithReplies(for: postId)
            self.comments = fetchedComments
        } catch {
            handleError(error)
        }
    }
    
    /// Add a comment to a post
    func addComment(to postId: String, content: String, mentionedUserIds: [String]? = nil) async {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            _ = try await commentService.addComment(
                postId: postId,
                content: content,
                mentionedUserIds: mentionedUserIds
            )
            
            // Refresh comments
            await fetchComments(for: postId)
        } catch {
            handleError(error)
        }
    }
    
    /// Add a reply to a comment
    func addReply(
        to commentId: String,
        in postId: String,
        content: String,
        mentionedUserIds: [String]? = nil
    ) async {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            _ = try await commentService.addReply(
                postId: postId,
                parentCommentId: commentId,
                content: content,
                mentionedUserIds: mentionedUserIds
            )
            
            // Refresh comments
            await fetchComments(for: postId)
        } catch {
            handleError(error)
        }
    }
    
    /// Toggle amen on a comment
    func toggleCommentAmen(_ commentId: String) async {
        do {
            try await commentService.toggleAmen(commentId: commentId)
        } catch {
            handleError(error)
        }
    }
    
    /// Delete a comment
    func deleteComment(_ commentId: String, from postId: String) async {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            try await commentService.deleteComment(commentId: commentId, postId: postId)
            
            // Refresh comments
            await fetchComments(for: postId)
        } catch {
            handleError(error)
        }
    }
    
    /// Start listening to comments for a post
    func startListeningToComments(for postId: String) {
        commentService.startListening(to: postId)
        
        // Bind comment updates
        commentService.$comments
            .compactMap { (commentsDict: [String: [Comment]]) -> [Comment]? in
                return commentsDict[postId]
            }
            .sink { [weak self] (updatedComments: [Comment]) in
                // Convert to CommentWithReplies
                let grouped = Dictionary(grouping: updatedComments) { $0.parentCommentId == nil }
                let topLevel = grouped[true] ?? []
                let replies = grouped[false] ?? []
                
                self?.comments = topLevel.map { comment in
                    let commentReplies = replies.filter { $0.parentCommentId == comment.id }
                    return CommentWithReplies(comment: comment, replies: commentReplies)
                }
            }
            .store(in: &cancellables)
    }
    
    /// Stop listening to comments
    func stopListeningToComments() {
        commentService.stopListening()
    }
    
    // MARK: - Saved Posts
    
    /// Fetch user's saved posts
    func fetchSavedPosts() async {
        do {
            _ = try await savedPostsService.fetchSavedPosts()
        } catch {
            handleError(error)
        }
    }
    
    /// Save a post
    func savePost(_ postId: String, to collection: String? = nil) async {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            try await savedPostsService.savePost(postId: postId, collection: collection)
        } catch {
            handleError(error)
        }
    }
    
    /// Unsave a post
    func unsavePost(_ postId: String) async {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            try await savedPostsService.unsavePost(postId: postId)
        } catch {
            handleError(error)
        }
    }
    
    /// Toggle save status
    func toggleSavePost(_ postId: String) async {
        if savedPostIds.contains(postId) {
            await unsavePost(postId)
        } else {
            await savePost(postId)
        }
    }
    
    /// Check if a post is saved
    func isPostSaved(_ postId: String) -> Bool {
        savedPostIds.contains(postId)
    }
    
    /// Start listening to saved posts
    func startListeningToSavedPosts() {
        savedPostsService.startListening()
    }
    
    /// Stop listening to saved posts
    func stopListeningToSavedPosts() {
        savedPostsService.stopListening()
    }
    
    // MARK: - Reposts
    
    /// Fetch user's reposts
    func fetchReposts() async {
        do {
            _ = try await repostService.fetchUserReposts()
        } catch {
            handleError(error)
        }
    }
    
    /// Repost a post
    func repost(_ postId: String, withComment comment: String? = nil) async {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            try await repostService.repost(postId: postId, withComment: comment)
        } catch {
            handleError(error)
        }
    }
    
    /// Unrepost a post
    func unrepost(_ postId: String) async {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            try await repostService.unrepost(postId: postId)
        } catch {
            handleError(error)
        }
    }
    
    /// Toggle repost status
    func toggleRepost(_ postId: String, withComment comment: String? = nil) async {
        if repostedPostIds.contains(postId) {
            await unrepost(postId)
        } else {
            await repost(postId, withComment: comment)
        }
    }
    
    /// Check if user has reposted
    func hasReposted(_ postId: String) -> Bool {
        repostedPostIds.contains(postId)
    }
    
    /// Start listening to reposts
    func startListeningToReposts() {
        repostService.startListening()
    }
    
    /// Stop listening to reposts
    func stopListeningToReposts() {
        repostService.stopListening()
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ error: Error) {
        print("❌ PostInteractions Error: \(error.localizedDescription)")
        errorMessage = error.localizedDescription
        showError = true
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        stopListeningToComments()
        stopListeningToSavedPosts()
        stopListeningToReposts()
        cancellables.removeAll()
    }
}
