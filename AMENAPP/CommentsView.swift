//
//  CommentsView.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  View for displaying and managing comments and replies on a post
//

import SwiftUI
import FirebaseAuth

struct CommentsView: View {
    let post: Post
    
    @StateObject private var commentService = CommentService.shared
    @StateObject private var userService = UserService.shared // ✅ Use shared instance instead of environment
    
    @State private var commentText = ""
    @State private var replyingTo: Comment?
    @State private var commentsWithReplies: [CommentWithReplies] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isListening = false
    
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Comments")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.black)
                
                Spacer()
                
                Text("\(commentsWithReplies.count)")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.black.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(red: 0.98, green: 0.98, blue: 0.98))
            
            Divider()
            
            // Comments List
            ScrollView {
                LazyVStack(spacing: 0) {
                    if isLoading {
                        ProgressView()
                            .padding(.top, 40)
                    } else if commentsWithReplies.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 48))
                                .foregroundStyle(.black.opacity(0.3))
                            
                            Text("No comments yet")
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.black.opacity(0.6))
                            
                            Text("Be the first to comment!")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.black.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        ForEach(commentsWithReplies) { commentWithReplies in
                            VStack(alignment: .leading, spacing: 8) {
                                // Main Comment
                                PostCommentRow(
                                    comment: commentWithReplies.comment,
                                    onReply: {
                                        replyingTo = commentWithReplies.comment
                                        isInputFocused = true
                                    },
                                    onDelete: {
                                        deleteComment(commentWithReplies.comment)
                                    },
                                    onAmen: {
                                        toggleAmen(comment: commentWithReplies.comment)
                                    }
                                )
                                
                                // Replies
                                if !commentWithReplies.replies.isEmpty {
                                    VStack(spacing: 0) {
                                        ForEach(Array(commentWithReplies.replies.enumerated()), id: \.offset) { index, reply in
                                            HStack(spacing: 0) {
                                                // Reply indicator line
                                                Rectangle()
                                                    .fill(.black.opacity(0.1))
                                                    .frame(width: 2)
                                                    .padding(.leading, 28)
                                                
                                                PostCommentRow(
                                                    comment: reply,
                                                    isReply: true,
                                                    onReply: {
                                                        replyingTo = commentWithReplies.comment
                                                        isInputFocused = true
                                                    },
                                                    onDelete: {
                                                        deleteComment(reply)
                                                    },
                                                    onAmen: {
                                                        toggleAmen(comment: reply)
                                                    }
                                                )
                                            }
                                            .id("reply-\(commentWithReplies.id)-\(index)")
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                            .id("comment-\(commentWithReplies.id)")
                            
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input Area
            VStack(spacing: 0) {
                // Replying indicator
                if let replyingTo = replyingTo {
                    HStack {
                        Text("Replying to \(replyingTo.authorUsername.hasPrefix("@") ? replyingTo.authorUsername : "@\(replyingTo.authorUsername)")")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.black.opacity(0.6))
                        
                        Spacer()
                        
                        Button {
                            self.replyingTo = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.black.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.95, green: 0.95, blue: 0.95))
                }
                
                // Input field
                HStack(alignment: .bottom, spacing: 12) {
                    // User avatar
                    Circle()
                        .fill(.black.opacity(0.1))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(userService.currentUser?.initials ?? "??")
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(.black.opacity(0.6))
                        )
                    
                    // Text field
                    TextField(replyingTo != nil ? "Write a reply..." : "Add a comment...", text: $commentText, axis: .vertical)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .lineLimit(1...4)
                        .focused($isInputFocused)
                    
                    // Send button
                    Button {
                        submitComment()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(commentText.isEmpty ? .black.opacity(0.3) : .black)
                    }
                    .disabled(commentText.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white)
            }
        }
        .background(Color.white)
        .task {
            await loadComments()
            startRealtimeListener()
        }
        .onDisappear {
            stopRealtimeListener()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Actions
    
    private func loadComments() async {
        isLoading = true
        do {
            commentsWithReplies = try await commentService.fetchCommentsWithReplies(for: post.id.uuidString)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    private func submitComment() {
        guard !commentText.isEmpty else { return }
        
        let text = commentText
        commentText = ""
        
        Task {
            do {
                if let replyingTo = replyingTo {
                    // Submit reply
                    _ = try await commentService.addReply(
                        postId: post.id.uuidString,
                        parentCommentId: replyingTo.id ?? "",
                        content: text
                    )
                    
                    // Real-time listener will update UI automatically!
                    self.replyingTo = nil
                } else {
                    // Submit comment
                    _ = try await commentService.addComment(
                        postId: post.id.uuidString,
                        content: text
                    )
                    
                    // Real-time listener will update UI automatically!
                }
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                
                // Restore text on error
                commentText = text
            }
        }
    }
    
    private func deleteComment(_ comment: Comment) {
        Task {
            do {
                try await commentService.deleteComment(commentId: comment.id ?? "", postId: post.id.uuidString)
                
                // Real-time listener will update UI automatically!
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func toggleAmen(comment: Comment) {
        Task {
            do {
                try await commentService.toggleAmen(commentId: comment.id ?? "")
                
                // Update local UI
                if comment.isReply {
                    // Find and update reply
                    for i in 0..<commentsWithReplies.count {
                        if let replyIndex = commentsWithReplies[i].replies.firstIndex(where: { $0.id == comment.id }) {
                            var updatedReply = commentsWithReplies[i].replies[replyIndex]
                            let hasAmened = await commentService.hasUserAmened(commentId: comment.id ?? "")
                            updatedReply.amenCount += hasAmened ? 1 : -1
                            commentsWithReplies[i].replies[replyIndex] = updatedReply
                        }
                    }
                } else {
                    // Find and update comment
                    if let index = commentsWithReplies.firstIndex(where: { $0.comment.id == comment.id }) {
                        var updatedComment = commentsWithReplies[index].comment
                        let hasAmened = await commentService.hasUserAmened(commentId: comment.id ?? "")
                        updatedComment.amenCount += hasAmened ? 1 : -1
                        commentsWithReplies[index] = CommentWithReplies(comment: updatedComment, replies: commentsWithReplies[index].replies)
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    // MARK: - Real-time Updates
    
    private func startRealtimeListener() {
        guard !isListening else { return }
        
        print("🔊 CommentsView: Starting real-time listener for post: \(post.id.uuidString)")
        commentService.startListening(to: post.id.uuidString)
        isListening = true
        
        // Observe changes to commentService.comments and update UI
        Task {
            // Poll for updates every second (not ideal, but works with current setup)
            while isListening {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                await updateCommentsFromService()
            }
        }
    }
    
    private func stopRealtimeListener() {
        guard isListening else { return }
        
        print("🔇 CommentsView: Stopping real-time listener")
        commentService.stopListening()
        isListening = false
    }
    
    @MainActor
    private func updateCommentsFromService() async {
        // Get updated comments from service cache
        let updatedComments = commentService.comments[post.id.uuidString] ?? []
        
        // Build commentsWithReplies from service data
        var newCommentsWithReplies: [CommentWithReplies] = []
        
        for comment in updatedComments {
            guard let commentId = comment.id else { continue }
            let replies = commentService.commentReplies[commentId] ?? []
            
            // Update reply count
            var updatedComment = comment
            updatedComment.replyCount = replies.count
            
            let commentWithReplies = CommentWithReplies(comment: updatedComment, replies: replies)
            newCommentsWithReplies.append(commentWithReplies)
        }
        
        // Only update if there are actual changes
        if newCommentsWithReplies.count != commentsWithReplies.count ||
           !areCommentsEqual(newCommentsWithReplies, commentsWithReplies) {
            commentsWithReplies = newCommentsWithReplies
            print("✅ CommentsView: Updated with \(commentsWithReplies.count) comments")
        }
    }
    
    private func areCommentsEqual(_ lhs: [CommentWithReplies], _ rhs: [CommentWithReplies]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        
        for i in 0..<lhs.count {
            if lhs[i].comment.id != rhs[i].comment.id ||
               lhs[i].replies.count != rhs[i].replies.count {
                return false
            }
        }
        
        return true
    }
}

// MARK: - Comment Row

private struct PostCommentRow: View {
    let comment: Comment
    var isReply: Bool = false
    let onReply: () -> Void
    let onDelete: () -> Void
    let onAmen: () -> Void
    
    @State private var showOptions = false
    
    private var isOwnComment: Bool {
        comment.authorId == FirebaseManager.shared.currentUser?.uid
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            if let imageURL = comment.authorProfileImageURL,
               let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(.black.opacity(0.1))
                        .overlay(
                            Text(comment.authorInitials)
                                .font(.custom("OpenSans-SemiBold", size: isReply ? 10 : 12))
                                .foregroundStyle(.black.opacity(0.6))
                        )
                }
                .frame(width: isReply ? 28 : 36, height: isReply ? 28 : 36)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(.black.opacity(0.1))
                    .frame(width: isReply ? 28 : 36, height: isReply ? 28 : 36)
                    .overlay(
                        Text(comment.authorInitials)
                            .font(.custom("OpenSans-SemiBold", size: isReply ? 10 : 12))
                            .foregroundStyle(.black.opacity(0.6))
                    )
            }
            
            VStack(alignment: .leading, spacing: 6) {
                // Author and time
                HStack(spacing: 8) {
                    Text(comment.authorName)
                        .font(.custom("OpenSans-SemiBold", size: isReply ? 13 : 14))
                        .foregroundStyle(.black)
                    
                    Text(comment.authorUsername.hasPrefix("@") ? comment.authorUsername : "@\(comment.authorUsername)")
                        .font(.custom("OpenSans-Regular", size: isReply ? 11 : 12))
                        .foregroundStyle(.black.opacity(0.5))
                    
                    Text("•")
                        .font(.custom("OpenSans-Regular", size: isReply ? 11 : 12))
                        .foregroundStyle(.black.opacity(0.3))
                    
                    Text(comment.timeAgo)
                        .font(.custom("OpenSans-Regular", size: isReply ? 11 : 12))
                        .foregroundStyle(.black.opacity(0.5))
                }
                
                // Content
                Text(comment.content)
                    .font(.custom("OpenSans-Regular", size: isReply ? 13 : 14))
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Actions
                HStack(spacing: 16) {
                    // Amen
                    Button {
                        onAmen()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "hands.clap")
                                .font(.system(size: 12))
                            
                            if comment.amenCount > 0 {
                                Text("\(comment.amenCount)")
                                    .font(.custom("OpenSans-Regular", size: 12))
                            }
                        }
                        .foregroundStyle(.black.opacity(0.6))
                    }
                    
                    // Reply
                    if !isReply {
                        Button {
                            onReply()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.system(size: 12))
                                
                                if comment.replyCount > 0 {
                                    Text("\(comment.replyCount)")
                                        .font(.custom("OpenSans-Regular", size: 12))
                                }
                            }
                            .foregroundStyle(.black.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                    
                    // Options (delete if own comment)
                    if isOwnComment {
                        Button {
                            showOptions = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12))
                                .foregroundStyle(.black.opacity(0.6))
                        }
                        .confirmationDialog("Comment Options", isPresented: $showOptions) {
                            Button("Delete Comment", role: .destructive) {
                                onDelete()
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, isReply ? 12 : 16)
    }
}

#Preview {
    CommentsView(post: Post(
        authorName: "Test User",
        authorInitials: "TU",
        content: "Test post",
        category: .openTable
    ))
    .environmentObject(UserService())
}
