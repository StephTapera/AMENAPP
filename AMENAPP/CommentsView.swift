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
import Combine

struct CommentsView: View {
    let post: Post
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var commentService = CommentService.shared
    @StateObject private var userService = UserService.shared // ✅ Use shared instance instead of environment
    
    @State private var commentText = ""
    @State private var replyingTo: Comment?
    @State private var commentsWithReplies: [CommentWithReplies] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isListening = false
    @State private var currentUserProfileImageURL: String?
    @State private var currentUserInitials: String = "U"
    @State private var selectedUserId: String?
    @State private var showUserProfile = false
    @State private var pollingTask: Task<Void, Never>?  // ✅ Store polling task
    @State private var expandedThreads: Set<String> = []  // Track expanded reply threads
    @State private var newCommentIds: Set<String> = []  // Track newly added comments for animation
    @State private var scrollProxy: ScrollViewProxy?  // For smooth scrolling to replies
    @Namespace private var animationNamespace  // For matched geometry effects
    
    // ✅ Timestamp auto-refresh (updates "5m ago" -> "6m ago")
    @State private var currentTime = Date()
    
    private var postId: String { post.firestoreId }
    
    @FocusState private var isInputFocused: Bool
    
    // MARK: - Top Participants Algorithm
    
    /// Computes top 8-12 participants to show in avatar row
    /// Priority: Post author > Recent commenters > Frequent commenters > Followed users > High-reaction comments
    private var topParticipants: [ParticipantInfo] {
        var participants: [ParticipantInfo] = []
        var seenUserIds = Set<String>()
        
        // 1. Always include post author first
        if !post.authorId.isEmpty, !seenUserIds.contains(post.authorId) {
            participants.append(ParticipantInfo(
                userId: post.authorId,
                initials: post.authorInitials,
                profileImageURL: post.authorProfileImageURL,
                score: 1000 // Highest priority
            ))
            seenUserIds.insert(post.authorId)
        }
        
        // 2. Collect all unique commenters with scores
        var userScores: [String: (info: ParticipantInfo, score: Double)] = [:]
        
        for (index, commentWithReplies) in commentsWithReplies.enumerated() {
            let comment = commentWithReplies.comment
            
            if !seenUserIds.contains(comment.authorId) {
                let recencyScore = Double(commentsWithReplies.count - index) * 2.0 // Recent = higher
                let reactionScore = Double(comment.amenCount) * 1.5
                let replyScore = Double(comment.replyCount) * 1.0
                let totalScore = recencyScore + reactionScore + replyScore
                
                let info = ParticipantInfo(
                    userId: comment.authorId,
                    initials: comment.authorInitials,
                    profileImageURL: comment.authorProfileImageURL,
                    score: totalScore
                )
                
                if let existing = userScores[comment.authorId] {
                    // Update score if this comment has better metrics
                    if totalScore > existing.score {
                        userScores[comment.authorId] = (info, totalScore)
                    }
                } else {
                    userScores[comment.authorId] = (info, totalScore)
                }
            }
            
            // Also check replies
            for reply in commentWithReplies.replies {
                if !seenUserIds.contains(reply.authorId) {
                    let reactionScore = Double(reply.amenCount) * 1.5
                    let totalScore = reactionScore + 1.0 // Base score for replying
                    
                    let info = ParticipantInfo(
                        userId: reply.authorId,
                        initials: reply.authorInitials,
                        profileImageURL: reply.authorProfileImageURL,
                        score: totalScore
                    )
                    
                    if let existing = userScores[reply.authorId] {
                        if totalScore > existing.score {
                            userScores[reply.authorId] = (info, totalScore)
                        }
                    } else {
                        userScores[reply.authorId] = (info, totalScore)
                    }
                }
            }
        }
        
        // 3. Sort by score and add top participants
        let sortedUsers = userScores.values
            .sorted { $0.score > $1.score }
            .prefix(11) // Get top 11 (since author is already added)
        
        for userScore in sortedUsers {
            if !seenUserIds.contains(userScore.info.userId) {
                participants.append(userScore.info)
                seenUserIds.insert(userScore.info.userId)
            }
        }
        
        // Limit to 12 total avatars
        return Array(participants.prefix(12))
    }
    
    // MARK: - Top Avatar Row
    
    private var topAvatarRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(topParticipants, id: \.id) { participant in
                    Button {
                        selectedUserId = participant.userId
                        showUserProfile = true
                        
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        if let imageURL = participant.profileImageURL,
                           !imageURL.isEmpty,
                           let url = URL(string: imageURL) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 52, height: 52)
                                        .clipShape(Circle())
                                case .failure, .empty:
                                    Circle()
                                        .fill(.black)
                                        .frame(width: 52, height: 52)
                                        .overlay(
                                            Text(participant.initials)
                                                .font(.custom("OpenSans-SemiBold", size: 16))
                                                .foregroundStyle(.white)
                                        )
                                @unknown default:
                                    Circle()
                                        .fill(.black)
                                        .frame(width: 52, height: 52)
                                        .overlay(
                                            Text(participant.initials)
                                                .font(.custom("OpenSans-SemiBold", size: 16))
                                                .foregroundStyle(.white)
                                        )
                                }
                            }
                        } else {
                            Circle()
                                .fill(.black)
                                .frame(width: 52, height: 52)
                                .overlay(
                                    Text(participant.initials)
                                        .font(.custom("OpenSans-SemiBold", size: 16))
                                        .foregroundStyle(.white)
                                )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
    
    // MARK: - Header with Avatar Row
    
    private var headerView: some View {
        VStack(spacing: 0) {
            // Avatar Row
            topAvatarRow
            
            Divider()
                .padding(.horizontal, 20)
            
            // Header with title and actions
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Comments")
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.black)
                    
                    Text("for \(post.authorName)")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.black.opacity(0.5))
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Bookmark button
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        Image(systemName: "bookmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.black.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color(white: 0.93))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                                    )
                            )
                    }
                    
                    // Share button
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.black.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color(white: 0.93))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                                    )
                            )
                    }
                    
                    // Close button
                    Button {
                        dismiss()
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.yellow)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                                    )
                            )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white)
            
            Divider()
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            // Comments List with ScrollViewReader for smooth scrolling
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if isLoading {
                            ProgressView()
                                .padding(.top, 40)
                                .transition(.opacity.combined(with: .scale))
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
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        } else {
                            ForEach(commentsWithReplies, id: \.id) { commentWithReplies in
                                VStack(alignment: .leading, spacing: 8) {
                                    // Main Comment with animation
                                    PostCommentRow(
                                        comment: commentWithReplies.comment,
                                        isNew: newCommentIds.contains(commentWithReplies.comment.id ?? ""),
                                        onReply: {
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                                replyingTo = commentWithReplies.comment
                                                isInputFocused = true
                                            }
                                            
                                            // Haptic feedback
                                            let haptic = UIImpactFeedbackGenerator(style: .light)
                                            haptic.impactOccurred()
                                        },
                                        onDelete: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                deleteComment(commentWithReplies.comment)
                                            }
                                        },
                                        onAmen: {
                                            toggleAmen(comment: commentWithReplies.comment)
                                        },
                                        onProfileTap: {
                                            selectedUserId = commentWithReplies.comment.authorId
                                            showUserProfile = true
                                        },
                                        onToggleThread: {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                if expandedThreads.contains(commentWithReplies.comment.id ?? "") {
                                                    expandedThreads.remove(commentWithReplies.comment.id ?? "")
                                                } else {
                                                    expandedThreads.insert(commentWithReplies.comment.id ?? "")
                                                }
                                            }
                                        },
                                        isThreadExpanded: expandedThreads.contains(commentWithReplies.comment.id ?? ""),
                                        replyCount: commentWithReplies.replies.count,
                                        currentTime: currentTime
                                    )
                                    .id("\(commentWithReplies.comment.id ?? "")-main")
                                    .transition(.asymmetric(
                                        insertion: .scale.combined(with: .opacity),
                                        removal: .scale.combined(with: .opacity)
                                    ))
                                    
                                    // Replies with expand/collapse animation
                                    if !commentWithReplies.replies.isEmpty && 
                                       expandedThreads.contains(commentWithReplies.comment.id ?? "") {
                                        VStack(spacing: 0) {
                                            ForEach(commentWithReplies.replies, id: \.id) { reply in
                                                HStack(spacing: 0) {
                                                    // Animated reply indicator line
                                                    Rectangle()
                                                        .fill(.black.opacity(0.1))
                                                        .frame(width: 2)
                                                        .padding(.leading, 28)
                                                        .transition(.scale(scale: 0.1, anchor: .top))
                                                    
                                                    PostCommentRow(
                                                        comment: reply,
                                                        isReply: true,
                                                        isNew: newCommentIds.contains(reply.id ?? ""),
                                                        onReply: {
                                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                                                replyingTo = commentWithReplies.comment
                                                                isInputFocused = true
                                                            }
                                                            
                                                            let haptic = UIImpactFeedbackGenerator(style: .light)
                                                            haptic.impactOccurred()
                                                        },
                                                        onDelete: {
                                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                                deleteComment(reply)
                                                            }
                                                        },
                                                        onAmen: {
                                                            toggleAmen(comment: reply)
                                                        },
                                                        onProfileTap: {
                                                            selectedUserId = reply.authorId
                                                            showUserProfile = true
                                                        },
                                                        currentTime: currentTime
                                                    )
                                                }
                                                .id("\(reply.id ?? "")-reply")
                                                .transition(.asymmetric(
                                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                                    removal: .move(edge: .leading).combined(with: .opacity)
                                                ))
                                            }
                                        }
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                    }
                                }
                                .padding(.vertical, 8)
                                .id(commentWithReplies.comment.id ?? UUID().uuidString)
                                
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                    }
                }
                .onAppear {
                    scrollProxy = proxy
                }
            }
            
            Divider()
            
            // Input Area with Liquid Glass Buttons
            VStack(spacing: 0) {
                // Replying indicator
                if let replyingTo = replyingTo {
                    HStack {
                        Text("Replying to \(replyingTo.authorUsername.hasPrefix("@") ? replyingTo.authorUsername : "@\(replyingTo.authorUsername)")")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.black.opacity(0.6))
                        
                        Spacer()
                        
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                self.replyingTo = nil
                            }
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
                
                // Input field with glass buttons
                HStack(alignment: .bottom, spacing: 12) {
                    // User avatar - Show actual profile photo
                    if let imageURL = currentUserProfileImageURL,
                       !imageURL.isEmpty,
                       let url = URL(string: imageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                            case .failure:
                                Circle()
                                    .fill(.black)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Text(currentUserInitials)
                                            .font(.custom("OpenSans-SemiBold", size: 14))
                                            .foregroundStyle(.white)
                                    )
                            case .empty:
                                Circle()
                                    .fill(.black.opacity(0.1))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    )
                            @unknown default:
                                Circle()
                                    .fill(.black)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Text(currentUserInitials)
                                            .font(.custom("OpenSans-SemiBold", size: 14))
                                            .foregroundStyle(.white)
                                    )
                            }
                        }
                    } else {
                        Circle()
                            .fill(.black)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text(currentUserInitials)
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.white)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        // Text field
                        TextField(replyingTo != nil ? "Write a reply..." : "Add a comment...", text: $commentText, axis: .vertical)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .lineLimit(1...4)
                            .focused($isInputFocused)
                        
                        // Action buttons row
                        HStack(spacing: 12) {
                            // Glass Action Pill (attachment options)
                            GlassActionPill(
                                icons: ["paperclip", "face.smiling", "photo"],
                                actions: [
                                    { print("Attach file") },
                                    { print("Add emoji") },
                                    { print("Add photo") }
                                ]
                            )
                            
                            Spacer()
                            
                            // Glass Circular Send Button
                            GlassCircularButton(
                                icon: "paperplane.fill",
                                action: {
                                    submitComment()
                                },
                                isDisabled: commentText.isEmpty
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(Color.white)
            }
        }
        .background(Color.white)
        .gesture(
            // Tap to dismiss keyboard
            TapGesture()
                .onEnded { _ in
                    if isInputFocused {
                        isInputFocused = false
                    }
                }
        )
        .sheet(isPresented: $showUserProfile) {
            if let userId = selectedUserId {
                UserProfileView(userId: userId)
            }
        }
        .task {
            print("🎬 [VIEW] CommentsView appeared for post: \(postId)")
            
            // ✅ Start real-time listener FIRST so it picks up cached data immediately
            startRealtimeListener()
            
            // Load current user data
            loadCurrentUserData()
            
            // ✅ DON'T call loadComments() - the real-time listener will populate the UI
            // The listener fires immediately with cached data, then updates with server data
        }
        .onDisappear {
            print("👋 [VIEW] CommentsView disappearing")
            stopRealtimeListener()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("commentsUpdated"))) { notification in
            // Check if this notification is for our post
            if let notificationPostId = notification.userInfo?["postId"] as? String,
               notificationPostId == self.postId {
                print("🔔 [REALTIME] Received comments update notification")
                // ✅ Add a small delay to ensure the service has finished updating commentReplies
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    await updateCommentsFromService()
                }
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            // ✅ Timestamp auto-refresh: Update current time every 60 seconds
            // This triggers view refresh, causing "5m ago" → "6m ago" updates
            currentTime = Date()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Load Current User Data
    
    private func loadCurrentUserData() {
        // Get cached user data
        currentUserInitials = UserDefaults.standard.string(forKey: "currentUserInitials") ?? "U"
        currentUserProfileImageURL = UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
        
        print("👤 Loaded current user data for comments input")
        print("   Initials: \(currentUserInitials)")
        print("   Profile Image URL: \(currentUserProfileImageURL ?? "none")")
    }
    
    // MARK: - Actions
    
    private func loadComments() async {
        print("📥 [LOAD] Loading comments for post: \(postId)")
        print("🔍 [DEBUG] Fetching from path: postInteractions/\(postId)/comments")
        isLoading = true
        do {
            commentsWithReplies = try await commentService.fetchCommentsWithReplies(for: postId)
            print("✅ [LOAD] Loaded \(commentsWithReplies.count) comments successfully")
            
            // Debug: Log each comment ID to verify they exist
            for comment in commentsWithReplies {
                print("   📝 Comment ID: \(comment.comment.id ?? "nil") - Content: \(comment.comment.content)")
            }
        } catch {
            print("❌ [LOAD] Error loading comments: \(error)")
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    private func submitComment() {
        guard !commentText.isEmpty else {
            print("⚠️ [COMMENT] Submit blocked - empty text")
            return
        }
        
        let text = commentText
        commentText = ""
        
        print("📝 [COMMENT] Starting submission process")
        print("   Post ID: \(postId)")
        print("   Content: \(text)")
        print("   Current comments count: \(commentsWithReplies.count)")
        
        Task {
            do {
                var newCommentId: String?
                
                if let replyingTo = replyingTo {
                    print("💬 [COMMENT] Submitting as REPLY to comment: \(replyingTo.id ?? "nil")")
                    // Validate parent comment ID
                    guard let parentCommentId = replyingTo.id, !parentCommentId.isEmpty else {
                        await MainActor.run {
                            errorMessage = "Invalid parent comment"
                            showError = true
                            commentText = text // Restore text
                        }
                        return
                    }
                    
                    // Submit reply
                    let newComment = try await commentService.addReply(
                        postId: postId,
                        parentCommentId: parentCommentId,
                        content: text
                    )
                    newCommentId = newComment.id
                    
                    // ✅ DON'T add reply to local UI - let the real-time listener handle it
                    await MainActor.run {
                        print("🎨 [REPLY] Reply created, waiting for real-time listener to update UI")
                        print("   Reply ID: \(newComment.id ?? "nil")")
                        print("   Parent ID: \(parentCommentId)")

                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            // Expand parent thread and clear reply state
                            expandedThreads.insert(parentCommentId)
                            self.replyingTo = nil
                            print("   📂 Thread will be expanded when listener adds reply")
                        }
                    }
                } else {
                    print("💬 [COMMENT] Submitting as TOP-LEVEL comment")
                    
                    // Submit comment
                    let newComment = try await commentService.addComment(
                        postId: postId,
                        content: text
                    )
                    newCommentId = newComment.id
                    
                    print("✅ [COMMENT] Comment created successfully!")
                    print("   Comment ID: \(newComment.id ?? "nil")")
                    print("   Author: \(newComment.authorName)")
                    print("   Content: \(newComment.content)")
                    
                    // ✅ DON'T add to local UI - let the real-time listener handle it
                    // The listener will pick up the new comment immediately from Firebase
                    await MainActor.run {
                        print("🎨 [COMMENT] Comment created, waiting for real-time listener to update UI")
                        print("   Comment ID: \(newComment.id ?? "nil")")
                        
                        // Expand thread by default for new top-level comments
                        if let id = newCommentId {
                            expandedThreads.insert(id)
                            print("   📂 Thread will be expanded when listener adds comment: \(id)")
                        }
                    }
                }
                
                // Track new comment for highlight animation
                if let id = newCommentId {
                    await MainActor.run {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                            newCommentIds.insert(id)
                        }
                        
                        // Remove highlight after 2 seconds
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            await MainActor.run {
                                withAnimation {
                                    newCommentIds.remove(id)
                                }
                            }
                        }
                        
                        // Scroll to new comment
                        if let scrollProxy = scrollProxy {
                            withAnimation(.easeOut(duration: 0.4)) {
                                scrollProxy.scrollTo("\(id)-main", anchor: .top)
                            }
                        }
                    }
                }
                
                // Haptic feedback
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                print("❌ [COMMENT] Error submitting comment: \(error)")
                print("   Error description: \(error.localizedDescription)")
                
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    
                    // Restore text on error
                    commentText = text
                    
                    print("   ⚠️ Text restored to input field")
                }
            }
        }
    }
    
    private func deleteComment(_ comment: Comment) {
        Task {
            guard let commentId = comment.id, !commentId.isEmpty else {
                await MainActor.run {
                    errorMessage = "Invalid comment ID"
                    showError = true
                }
                return
            }
            
            do {
                // ✅ OPTIMISTIC UPDATE: Remove from UI immediately for better UX
                await MainActor.run {
                    if comment.isReply, let parentId = comment.parentCommentId {
                        // Remove reply from parent's replies
                        for i in 0..<commentsWithReplies.count {
                            if commentsWithReplies[i].comment.id == parentId {
                                commentsWithReplies[i].replies.removeAll { $0.id == commentId }
                                break
                            }
                        }
                    } else {
                        // Remove top-level comment
                        commentsWithReplies.removeAll { $0.comment.id == commentId }
                    }
                }
                
                // Then delete from Firebase (real-time listener will confirm)
                try await commentService.deleteComment(commentId: commentId, postId: postId)
                
                // Haptic feedback
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                // If deletion failed, reload comments to restore state
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
                
                // ✅ DON'T reload - the real-time listener will restore the UI automatically
                // The optimistic delete already happened, listener will revert if delete failed
            }
        }
    }
    
    private func toggleAmen(comment: Comment) {
        // Optimistic UI update with animation
        let commentId = comment.id ?? ""
        
        // Haptic feedback immediately
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        Task {
            guard !commentId.isEmpty else {
                await MainActor.run {
                    errorMessage = "Invalid comment ID"
                    showError = true
                }
                return
            }
            
            do {
                // Get current amen status before toggling
                let wasAmened = await commentService.hasUserAmened(commentId: commentId, postId: postId)
                
                // Optimistic UI update
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        if comment.isReply {
                            // Find and update reply
                            for i in 0..<commentsWithReplies.count {
                                if let replyIndex = commentsWithReplies[i].replies.firstIndex(where: { $0.id == commentId }) {
                                    var updatedReply = commentsWithReplies[i].replies[replyIndex]
                                    updatedReply.amenCount += wasAmened ? -1 : 1
                                    commentsWithReplies[i].replies[replyIndex] = updatedReply
                                }
                            }
                        } else {
                            // Find and update comment
                            if let index = commentsWithReplies.firstIndex(where: { $0.comment.id == commentId }) {
                                var updatedComment = commentsWithReplies[index].comment
                                updatedComment.amenCount += wasAmened ? -1 : 1
                                commentsWithReplies[index] = CommentWithReplies(comment: updatedComment, replies: commentsWithReplies[index].replies)
                            }
                        }
                    }
                }
                
                // Sync to Firebase in background
                try await commentService.toggleAmen(commentId: commentId, postId: postId)
                
            } catch {
                // Revert on error
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if comment.isReply {
                            for i in 0..<commentsWithReplies.count {
                                if let replyIndex = commentsWithReplies[i].replies.firstIndex(where: { $0.id == commentId }) {
                                    var updatedReply = commentsWithReplies[i].replies[replyIndex]
                                    updatedReply.amenCount = comment.amenCount // Revert to original
                                    commentsWithReplies[i].replies[replyIndex] = updatedReply
                                }
                            }
                        } else {
                            if let index = commentsWithReplies.firstIndex(where: { $0.comment.id == commentId }) {
                                var updatedComment = commentsWithReplies[index].comment
                                updatedComment.amenCount = comment.amenCount // Revert to original
                                commentsWithReplies[index] = CommentWithReplies(comment: updatedComment, replies: commentsWithReplies[index].replies)
                            }
                        }
                    }
                    
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    // MARK: - Real-time Updates
    
    private func startRealtimeListener() {
        guard !isListening else { return }
        
        print("🔊 CommentsView: Starting real-time listener for post: \(postId)")
        commentService.startListening(to: postId)
        isListening = true
        
        // ✅ Reduced polling since we now have instant notification updates
        // This is just a safety fallback in case notifications are missed
        pollingTask = Task {
            while !Task.isCancelled && isListening {
                // Slow polling as fallback (5 seconds) - notifications handle instant updates
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
                
                await updateCommentsFromService()
            }
        }
    }
    
    private func stopRealtimeListener() {
        guard isListening else { return }
        
        print("🔇 CommentsView: Stopping real-time listener")
        
        // Cancel polling task
        pollingTask?.cancel()
        pollingTask = nil
        
        commentService.stopListening()
        isListening = false
    }
    
    @MainActor
    private func updateCommentsFromService() async -> Bool {
        // Get updated comments from service cache (only top-level comments)
        let allComments = commentService.comments[postId] ?? []
        
        print("🔄 [SYNC] Polling update from service")
        print("   Service has \(allComments.count) comments for this post")
        print("   Local UI has \(commentsWithReplies.count) comments")
        
        // Debug: Log current UI state
        for (index, cwrComment) in commentsWithReplies.enumerated() {
            print("   [UI-\(index)] ID: \(cwrComment.comment.id ?? "nil"), replies: \(cwrComment.replies.count), isReply: \(cwrComment.comment.parentCommentId != nil)")
        }
        
        // Build commentsWithReplies from service data
        var newCommentsWithReplies: [CommentWithReplies] = []
        
        for comment in allComments {
            guard let commentId = comment.id else {
                print("⚠️ [SYNC] Skipping comment with nil ID")
                continue
            }
            
            let replies = commentService.commentReplies[commentId] ?? []
            
            // Update reply count
            var updatedComment = comment
            updatedComment.replyCount = replies.count
            
            let commentWithReplies = CommentWithReplies(comment: updatedComment, replies: replies)
            newCommentsWithReplies.append(commentWithReplies)
        }
        
        print("   Built \(newCommentsWithReplies.count) comments with replies")
        
        // ✅ CRITICAL FIX: Only update if there are actual changes
        // This prevents duplicate IDs and unnecessary re-renders
        if hasCommentsChanged(newCommentsWithReplies) {
            print("   ✅ [SYNC] Changes detected - updating UI")
            withAnimation(.easeOut(duration: 0.25)) {
                commentsWithReplies = newCommentsWithReplies
            }
            print("   ✅ [SYNC] UI updated with \(commentsWithReplies.count) comments")
            return true
        } else {
            print("   ⏭️ [SYNC] No changes detected - skipping update")
        }
        
        return false
    }
    
    /// Check if comments have actually changed (prevents duplicate updates)
    private func hasCommentsChanged(_ newComments: [CommentWithReplies]) -> Bool {
        // Different count = changed
        if newComments.count != commentsWithReplies.count {
            print("   🔍 [CHANGE] Count changed: \(commentsWithReplies.count) → \(newComments.count)")
            return true
        }
        
        // Check if IDs match in order
        for i in 0..<newComments.count {
            guard i < commentsWithReplies.count else {
                print("   🔍 [CHANGE] Bounds check failed at index \(i)")
                return true
            }
            
            let newComment = newComments[i]
            let oldComment = commentsWithReplies[i]
            
            // Different comment ID = changed
            if newComment.comment.id != oldComment.comment.id {
                print("   🔍 [CHANGE] Comment ID changed at index \(i)")
                return true
            }
            
            // Different reply count = changed
            if newComment.replies.count != oldComment.replies.count {
                print("   🔍 [CHANGE] Reply count changed at index \(i): \(oldComment.replies.count) → \(newComment.replies.count)")
                return true
            }
            
            // Different amen count = changed
            if newComment.comment.amenCount != oldComment.comment.amenCount {
                print("   🔍 [CHANGE] Amen count changed at index \(i)")
                return true
            }
            
            // Check reply IDs with bounds checking
            for j in 0..<newComment.replies.count {
                guard j < oldComment.replies.count else {
                    print("   🔍 [CHANGE] Reply bounds check failed at \(i):\(j)")
                    return true
                }
                if newComment.replies[j].id != oldComment.replies[j].id {
                    print("   🔍 [CHANGE] Reply ID changed at \(i):\(j)")
                    return true
                }
            }
        }
        
        // No changes detected
        return false
    }
    
    // MARK: - Timestamp Auto-Refresh Helper
    
    /// ✅ Computes relative time string that updates when currentTime changes
    /// This creates a dependency on currentTime, so when the timer updates currentTime,
    /// this function re-evaluates and the UI shows updated timestamps
    private func timeAgoString(for date: Date) -> String {
        // Include currentTime in computation to create SwiftUI dependency
        let _ = currentTime
        
        // Use the standard timeAgoDisplay extension
        return date.timeAgoDisplay()
    }
}

// MARK: - Comment Row

private struct PostCommentRow: View {
    let comment: Comment
    var isReply: Bool = false
    var isNew: Bool = false
    let onReply: () -> Void
    let onDelete: () -> Void
    let onAmen: () -> Void
    let onProfileTap: () -> Void
    var onToggleThread: (() -> Void)? = nil
    var isThreadExpanded: Bool = true
    var replyCount: Int = 0
    var currentTime: Date = Date() // ✅ For timestamp auto-refresh
    
    @State private var showOptions = false
    @State private var hasAmened = false
    @State private var localAmenCount: Int = 0
    
    private var isOwnComment: Bool {
        comment.authorId == FirebaseManager.shared.currentUser?.uid
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar - Tappable to view profile
            Button {
                onProfileTap()
                
                // Haptic feedback
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
            } label: {
                if let imageURL = comment.authorProfileImageURL,
                   !imageURL.isEmpty,
                   let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: isReply ? 28 : 36, height: isReply ? 28 : 36)
                                .clipShape(Circle())
                        case .failure:
                            Circle()
                                .fill(.black)
                                .frame(width: isReply ? 28 : 36, height: isReply ? 28 : 36)
                                .overlay(
                                    Text(comment.authorInitials)
                                        .font(.custom("OpenSans-SemiBold", size: isReply ? 10 : 12))
                                        .foregroundStyle(.white)
                                )
                        case .empty:
                            Circle()
                                .fill(.black.opacity(0.1))
                                .frame(width: isReply ? 28 : 36, height: isReply ? 28 : 36)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.7)
                                )
                        @unknown default:
                            Circle()
                                .fill(.black)
                                .frame(width: isReply ? 28 : 36, height: isReply ? 28 : 36)
                                .overlay(
                                    Text(comment.authorInitials)
                                        .font(.custom("OpenSans-SemiBold", size: isReply ? 10 : 12))
                                        .foregroundStyle(.white)
                                )
                        }
                    }
                } else {
                    Circle()
                        .fill(.black)
                        .frame(width: isReply ? 28 : 36, height: isReply ? 28 : 36)
                        .overlay(
                            Text(comment.authorInitials)
                                .font(.custom("OpenSans-SemiBold", size: isReply ? 10 : 12))
                                .foregroundStyle(.white)
                        )
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 6) {
                // Author and time
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text(comment.authorName)
                            .font(.custom("OpenSans-SemiBold", size: isReply ? 13 : 14))
                            .foregroundStyle(.black)

                        // ✅ Verified badge
                        if VerifiedBadgeHelper.isVerified(userId: comment.authorId) {
                            VerifiedBadge(size: isReply ? 12 : 13)
                        }
                    }

                    Text(comment.authorUsername.hasPrefix("@") ? comment.authorUsername : "@\(comment.authorUsername)")
                        .font(.custom("OpenSans-Regular", size: isReply ? 11 : 12))
                        .foregroundStyle(.black.opacity(0.5))

                    Text("•")
                        .font(.custom("OpenSans-Regular", size: isReply ? 11 : 12))
                        .foregroundStyle(.black.opacity(0.3))

                    // ✅ Timestamp auto-refresh: Recomputes when currentTime changes
                    Text(timeAgoString(for: comment.createdAt, currentTime: currentTime))
                        .font(.custom("OpenSans-Regular", size: isReply ? 11 : 12))
                        .foregroundStyle(.black.opacity(0.5))
                }
                
                // Content
                Text(comment.content)
                    .font(.custom("OpenSans-Regular", size: isReply ? 13 : 14))
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Actions
                HStack(spacing: 20) {
                    // Amen with animation (heart icon like reference)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                            hasAmened.toggle()
                        }
                        onAmen()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: hasAmened ? "heart.fill" : "heart")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(hasAmened ? Color.red : Color.black.opacity(0.5))
                                .scaleEffect(hasAmened ? 1.15 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: hasAmened)
                            
                            if comment.amenCount > 0 {
                                Text("\(comment.amenCount)")
                                    .font(.custom("OpenSans-Medium", size: 13))
                                    .foregroundStyle(hasAmened ? Color.red : Color.black.opacity(0.5))
                                    .contentTransition(.numericText())
                            }
                        }
                    }
                    
                    // Reply with count badge
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
                        
                        // Thread expand/collapse button
                        if replyCount > 0, let onToggleThread = onToggleThread {
                            Button {
                                onToggleThread()
                                
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isThreadExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                    
                                    Text(isThreadExpanded ? "Hide" : "View")
                                        .font(.custom("OpenSans-SemiBold", size: 11))
                                }
                                .foregroundStyle(.black.opacity(0.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.05))
                                )
                            }
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
    
    // Helper function to compute time ago string with currentTime dependency
    private func timeAgoString(for date: Date, currentTime: Date) -> String {
        let _ = currentTime // Create dependency on currentTime
        return date.timeAgoDisplay()
    }
<<<<<<< HEAD
}

// MARK: - Participant Info Model

struct ParticipantInfo: Identifiable {
    let id = UUID()
    let userId: String
    let initials: String
    let profileImageURL: String?
    let score: Double
=======
>>>>>>> origin/main
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
