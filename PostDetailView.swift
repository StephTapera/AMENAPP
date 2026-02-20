//
//  PostDetailView.swift
//  AMENAPP
//
//  Threads-inspired post detail view with glassmorphic design
//  Shows full post content with comments in a focused, distraction-free layout
//

import SwiftUI
import FirebaseAuth

struct PostDetailView: View {
    let post: Post
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var commentService = CommentService.shared
    @StateObject private var userService = UserService.shared
    @StateObject private var postsManager = PostsManager.shared
    
    @State private var commentsWithReplies: [CommentWithReplies] = []
    @State private var isLoading = false
    @State private var showShareSheet = false
    @State private var showCommentInput = false
    @State private var commentText = ""
    @State private var scrollToComments = false
    @FocusState private var isCommentFocused: Bool
    
    private var postId: String { post.firestoreId }
    
    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Main post content
                        mainPostSection
                            .id("post")
                        
                        // Engagement bar (reactions, comments, share)
                        engagementBar
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        
                        Divider()
                            .padding(.horizontal, 20)
                        
                        // Comments section
                        if isLoading {
                            loadingView
                        } else if commentsWithReplies.isEmpty {
                            emptyCommentsView
                        } else {
                            commentsSection
                                .id("comments")
                        }
                        
                        // Bottom spacing for comment input
                        Color.clear.frame(height: 80)
                    }
                }
                .onChange(of: scrollToComments) { _, shouldScroll in
                    if shouldScroll {
                        withAnimation {
                            proxy.scrollTo("comments", anchor: .top)
                        }
                        scrollToComments = false
                    }
                }
            }
            
            // Floating comment input bar
            VStack {
                Spacer()
                commentInputBar
            }
            .ignoresSafeArea(.keyboard)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                closeButton
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                shareButton
            }
        }
        .task {
            await loadComments()
        }
    }
    
    // MARK: - Main Post Section
    
    private var mainPostSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Author info
            HStack(spacing: 12) {
                // Profile image
                if let imageURL = post.authorProfileImageURL, !imageURL.isEmpty, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.black, Color.black.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .overlay(
                                Text(post.authorInitials)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                            )
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                } else {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.black, Color.black.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(post.authorInitials)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorUsername ?? post.authorName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text(timeAgo(from: post.createdAt))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            // Post content
            Text(post.content)
                .font(.system(size: 17))
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            
            // Post image if available
            if let imageURLs = post.imageURLs, let firstImage = imageURLs.first, !firstImage.isEmpty, let url = URL(string: firstImage) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 400)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                    case .failure(_):
                        EmptyView()
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                ProgressView()
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            
            // Topic tag
            if let topicTag = post.topicTag, !topicTag.isEmpty {
                Text("#\(topicTag)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }
    
    // MARK: - Engagement Bar
    
    private var engagementBar: some View {
        HStack(spacing: 24) {
            // Amen count
            HStack(spacing: 6) {
                Image(systemName: "hands.clap")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                
                Text("\(post.amenCount)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            // Comment count
            HStack(spacing: 6) {
                Image(systemName: "message")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                
                Text("\(post.commentCount)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .onTapGesture {
                showCommentInput = true
                isCommentFocused = true
            }
            
            Spacer()
            
            // Share button
            Button {
                showShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Comments Section
    
    private var commentsSection: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("Comments")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(commentsWithReplies.count)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            // Comments list
            LazyVStack(spacing: 12) {
                ForEach(commentsWithReplies, id: \.comment.id) { commentWithReplies in
                    CommentRowView(
                        comment: commentWithReplies.comment,
                        replies: commentWithReplies.replies,
                        postId: postId
                    )
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 12)
        }
    }
    
    private var emptyCommentsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("No comments yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            
            Text("Be the first to share your thoughts")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading comments...")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Comment Input Bar
    
    private var commentInputBar: some View {
        HStack(spacing: 12) {
            // User avatar
            if let imageURL = userService.currentUser?.profileImageURL, !imageURL.isEmpty, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(userService.currentUser?.initials ?? "U")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }
            
            // Text field
            TextField("Add a comment...", text: $commentText, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(1...4)
                .focused($isCommentFocused)
                .submitLabel(.send)
                .onSubmit {
                    submitComment()
                }
            
            // Send button
            if !commentText.isEmpty {
                Button {
                    submitComment()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.blue)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Glassmorphic background
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .opacity(0.95)
                
                // Gradient overlay
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Border
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
        )
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: -4)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: -2)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    // MARK: - Toolbar Items
    
    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
    }
    
    private var shareButton: some View {
        Button {
            showShareSheet = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadComments() async {
        isLoading = true
        do {
            commentsWithReplies = try await commentService.fetchCommentsWithReplies(for: postId)
        } catch {
            print("❌ Failed to load comments: \(error)")
        }
        isLoading = false
    }
    
    private func submitComment() {
        guard !commentText.isEmpty else { return }
        
        let text = commentText
        commentText = ""
        isCommentFocused = false
        
        Task {
            do {
                _ = try await commentService.addComment(postId: postId, content: text)
                await loadComments()
                scrollToComments = true
            } catch {
                print("❌ Failed to post comment: \(error)")
            }
        }
    }
    

    
    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d"
        } else {
            let weeks = Int(interval / 604800)
            return "\(weeks)w"
        }
    }
}

// MARK: - Comment Row View

struct CommentRowView: View {
    let comment: Comment
    let replies: [Comment]
    let postId: String
    
    @State private var showReplies = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main comment
            HStack(alignment: .top, spacing: 12) {
                // Avatar
                if let imageURL = comment.authorProfileImageURL, !imageURL.isEmpty, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.black, Color.black.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .overlay(
                                Text(comment.authorInitials)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                            )
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.black, Color.black.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text(comment.authorInitials)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    // Author and time
                    HStack(spacing: 8) {
                        Text(comment.authorUsername)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        
                        Text(timeAgo(from: comment.createdAt))
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                    
                    // Content
                    Text(comment.content)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .lineSpacing(2)
                    
                    // Actions
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "hands.clap")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            
                            if comment.amenCount > 0 {
                                Text("\(comment.amenCount)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if comment.replyCount > 0 {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showReplies.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("\(comment.replyCount) \(comment.replyCount == 1 ? "reply" : "replies")")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    
                                    Image(systemName: showReplies ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            
            // Replies
            if showReplies && !replies.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(replies, id: \.id) { reply in
                        HStack(alignment: .top, spacing: 12) {
                            // Connection line
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 2)
                                .padding(.leading, 18)
                            
                            // Reply content
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(reply.authorUsername)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    
                                    Text(timeAgo(from: reply.createdAt))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)
                                }
                                
                                Text(reply.content)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.primary)
                                    .lineSpacing(2)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
    }
    
    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d"
        }
    }
}
