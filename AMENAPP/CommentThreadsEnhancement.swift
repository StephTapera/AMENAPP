//
//  CommentThreadsEnhancement.swift
//  AMENAPP
//
//  Enhancement 2: Smart Comment Threads with Collapsible Replies
//

import SwiftUI
import FirebaseAuth

// MARK: - Comment Sort Option

enum CommentSortOption: String, CaseIterable {
    case newest = "Newest First"
    case oldest = "Oldest First"
    case mostReactions = "Most Reactions"
    case authorFirst = "Author First"
    
    var icon: String {
        switch self {
        case .newest: return "arrow.down"
        case .oldest: return "arrow.up"
        case .mostReactions: return "heart.fill"
        case .authorFirst: return "person.fill"
        }
    }
}

// MARK: - Enhanced Comments View with Threads

struct ThreadedCommentsView: View {
    let post: Post
    
    @StateObject private var commentService = CommentService.shared
    @StateObject private var userService = UserService.shared
    
    @State private var commentText = ""
    @State private var replyingTo: Comment?
    @State private var commentsWithReplies: [CommentWithReplies] = []
    @State private var collapsedThreads: Set<String> = []
    @State private var sortOption: CommentSortOption = .newest
    @State private var showSortMenu = false
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    @FocusState private var isInputFocused: Bool
    
    // Sorted comments based on selected option
    private var sortedComments: [CommentWithReplies] {
        switch sortOption {
        case .newest:
            return commentsWithReplies.sorted { (a: CommentWithReplies, b: CommentWithReplies) in
                a.comment.createdAt > b.comment.createdAt
            }
        case .oldest:
            return commentsWithReplies.sorted { (a: CommentWithReplies, b: CommentWithReplies) in
                a.comment.createdAt < b.comment.createdAt
            }
        case .mostReactions:
            return commentsWithReplies.sorted { (a: CommentWithReplies, b: CommentWithReplies) in
                a.comment.amenCount > b.comment.amenCount
            }
        case .authorFirst:
            let opComments = commentsWithReplies.filter { $0.comment.authorId == post.authorId }
            let otherComments = commentsWithReplies.filter { $0.comment.authorId != post.authorId }
            return opComments + otherComments.sorted { (a: CommentWithReplies, b: CommentWithReplies) in
                a.comment.createdAt > b.comment.createdAt
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Sort
            HStack {
                Text("Comments")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.black)
                
                Text("\(commentsWithReplies.count)")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.black.opacity(0.6))
                
                Spacer()
                
                // Sort Button
                Button {
                    showSortMenu = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: sortOption.icon)
                            .font(.system(size: 12))
                        Text(sortOption.rawValue)
                            .font(.custom("OpenSans-Medium", size: 13))
                    }
                    .foregroundStyle(.black.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .stroke(Color.black.opacity(0.2), lineWidth: 1)
                    )
                }
                .confirmationDialog("Sort Comments", isPresented: $showSortMenu) {
                    ForEach(CommentSortOption.allCases, id: \.self) { option in
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                sortOption = option
                            }
                        } label: {
                            HStack {
                                Image(systemName: option.icon)
                                Text(option.rawValue)
                            }
                        }
                    }
                }
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
                        EmptyCommentsState()
                    } else {
                        ForEach(sortedComments) { commentWithReplies in
                            ThreadedCommentCell(
                                commentWithReplies: commentWithReplies,
                                postAuthorId: post.authorId,
                                isCollapsed: collapsedThreads.contains(commentWithReplies.comment.id ?? ""),
                                onToggleCollapse: {
                                    toggleThread(commentWithReplies.comment.id ?? "")
                                },
                                onReply: { comment in
                                    replyingTo = comment
                                    isInputFocused = true
                                },
                                onDelete: { comment in
                                    deleteComment(comment)
                                },
                                onAmen: { comment in
                                    toggleAmen(comment: comment)
                                }
                            )
                            
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input Area
            CommentInputBar(
                commentText: $commentText,
                replyingTo: $replyingTo,
                isInputFocused: $isInputFocused,
                userService: userService,
                onSubmit: submitComment
            )
        }
        .background(Color.white)
        .task {
            await loadComments()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Actions
    
    private func toggleThread(_ commentId: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            if collapsedThreads.contains(commentId) {
                collapsedThreads.remove(commentId)
            } else {
                collapsedThreads.insert(commentId)
            }
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
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
                    _ = try await commentService.addReply(
                        postId: post.id.uuidString,
                        parentCommentId: replyingTo.id ?? "",
                        content: text
                    )
                    self.replyingTo = nil
                } else {
                    _ = try await commentService.addComment(
                        postId: post.id.uuidString,
                        content: text
                    )
                }
                
                await loadComments()
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                commentText = text
            }
        }
    }
    
    private func deleteComment(_ comment: Comment) {
        Task {
            do {
                try await commentService.deleteComment(commentId: comment.id ?? "", postId: post.id.uuidString)
                await loadComments()
                
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
                try await commentService.toggleAmen(commentId: comment.id ?? "", postId: post.id.uuidString)
                await loadComments()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Threaded Comment Cell

struct ThreadedCommentCell: View {
    let commentWithReplies: CommentWithReplies
    let postAuthorId: String
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    let onReply: (Comment) -> Void
    let onDelete: (Comment) -> Void
    let onAmen: (Comment) -> Void
    
    private var isOP: Bool {
        commentWithReplies.comment.authorId == postAuthorId
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Comment
            HStack(alignment: .top, spacing: 0) {
                // Collapse button (if has replies)
                if !commentWithReplies.replies.isEmpty {
                    Button {
                        onToggleCollapse()
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.5))
                            .frame(width: 24, height: 24)
                    }
                    .padding(.leading, 8)
                } else {
                    Spacer()
                        .frame(width: 32)
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    EnhancedCommentContent(
                        comment: commentWithReplies.comment,
                        isOP: isOP,
                        onReply: { onReply(commentWithReplies.comment) },
                        onDelete: { onDelete(commentWithReplies.comment) },
                        onAmen: { onAmen(commentWithReplies.comment) }
                    )
                    
                    // Collapsed indicator
                    if isCollapsed && !commentWithReplies.replies.isEmpty {
                        Text("--- \(commentWithReplies.replies.count) \(commentWithReplies.replies.count == 1 ? "reply" : "replies") hidden ---")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.black.opacity(0.4))
                            .padding(.top, 8)
                            .padding(.leading, 48)
                    }
                }
            }
            
            // Replies (if not collapsed)
            if !isCollapsed && !commentWithReplies.replies.isEmpty {
                ForEach(commentWithReplies.replies, id: \.id) { reply in
                    HStack(spacing: 0) {
                        // Thread line
                        VStack {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(0.15),
                                            Color.black.opacity(0.05)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 2)
                        }
                        .padding(.leading, 28)
                        .padding(.trailing, 8)
                        
                        EnhancedCommentContent(
                            comment: reply,
                            isOP: reply.authorId == postAuthorId,
                            isReply: true,
                            onReply: { onReply(commentWithReplies.comment) },
                            onDelete: { onDelete(reply) },
                            onAmen: { onAmen(reply) }
                        )
                    }
                }
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Enhanced Comment Content

struct EnhancedCommentContent: View {
    let comment: Comment
    let isOP: Bool
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
            CommentAvatar(comment: comment, isReply: isReply)
            
            VStack(alignment: .leading, spacing: 8) {
                // Header with OP badge
                HStack(spacing: 8) {
                    Text(comment.authorName)
                        .font(.custom("OpenSans-SemiBold", size: isReply ? 13 : 14))
                        .foregroundStyle(.black)
                    
                    if isOP {
                        Text("OP")
                            .font(.custom("OpenSans-Bold", size: 10))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .blue.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                    }
                    
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
                
                // Content with link detection
                CommentContentText(comment.content, isReply: isReply)
                
                // Actions
                CommentActions(
                    comment: comment,
                    isReply: isReply,
                    isOwnComment: isOwnComment,
                    onReply: onReply,
                    onDelete: onDelete,
                    onAmen: onAmen
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Comment Content with Link Detection

struct CommentContentText: View {
    let content: String
    let isReply: Bool
    
    init(_ content: String, isReply: Bool = false) {
        self.content = content
        self.isReply = isReply
    }
    
    var body: some View {
        Text(content)
            .font(.custom("OpenSans-Regular", size: isReply ? 13 : 14))
            .foregroundStyle(.black)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled) // Allow text selection
    }
}

// MARK: - Comment Actions Row

struct CommentActions: View {
    let comment: Comment
    let isReply: Bool
    let isOwnComment: Bool
    let onReply: () -> Void
    let onDelete: () -> Void
    let onAmen: () -> Void
    
    @State private var showOptions = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Amen
            Button {
                onAmen()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "hands.clap.fill")
                        .font(.system(size: 12))
                    
                    if comment.amenCount > 0 {
                        Text("\(comment.amenCount)")
                            .font(.custom("OpenSans-Medium", size: 12))
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
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.system(size: 12))
                        
                        if comment.replyCount > 0 {
                            Text("\(comment.replyCount)")
                                .font(.custom("OpenSans-Medium", size: 12))
                        }
                    }
                    .foregroundStyle(.black.opacity(0.6))
                }
            }
            
            Spacer()
            
            // Options
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
}

// MARK: - Empty State

struct EmptyCommentsState: View {
    var body: some View {
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
    }
}

// MARK: - Comment Input Bar

struct CommentInputBar: View {
    @Binding var commentText: String
    @Binding var replyingTo: Comment?
    var isInputFocused: FocusState<Bool>.Binding
    let userService: UserService
    let onSubmit: () -> Void
    
    var body: some View {
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
                Circle()
                    .fill(.black.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(userService.currentUser?.initials ?? "??")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(.black.opacity(0.6))
                    )
                
                TextField(replyingTo != nil ? "Write a reply..." : "Add a comment...", text: $commentText, axis: .vertical)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .lineLimit(1...4)
                    .focused(isInputFocused)
                
                Button {
                    onSubmit()
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
}
// MARK: - Comment Avatar

private struct CommentAvatar: View {
    let comment: Comment
    let isReply: Bool
    
    var body: some View {
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
    }
}

