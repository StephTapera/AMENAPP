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
import PhotosUI

struct CommentsView: View {
    let post: Post
    
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var commentService = CommentService.shared  // P0 FIX: ObservedObject for singletons (faster init)
    @ObservedObject private var userService = UserService.shared  // P0 FIX: ObservedObject for singletons (faster init)
    
    // P0 FIX: Lazy load AI services - only initialize when needed, not on sheet open
    @State private var summarizationService: AIThreadSummarizationService?
    @State private var toneGuidanceService: AIToneGuidanceService?
    
    @State private var commentText = ""
    @State private var replyingTo: Comment?
    @State private var commentsWithReplies: [CommentWithReplies] = []
    @State private var isLoading = true  // P1 FIX: Start as true to show skeleton immediately
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isListening = false
    
    // P0-1 FIX: Prevent duplicate submissions
    @State private var isSubmittingComment = false
    @State private var currentUserProfileImageURL: String?
    @State private var currentUserInitials: String = "U"
    @State private var selectedUserId: String?
    @State private var showUserProfile = false
    @State private var pollingTask: Task<Void, Never>?  // ✅ Store polling task
    @State private var expandedThreads: Set<String> = []  // Track expanded reply threads
    @State private var newCommentIds: Set<String> = []  // Track newly added comments for animation
    @State private var scrollProxy: ScrollViewProxy?  // For smooth scrolling to replies
    @Namespace private var animationNamespace  // For matched geometry effects
    @State private var threadSummaries: [String: AIThreadSummarizationService.ThreadSummary] = [:]  // Cache thread summaries
    
    // ✅ Timestamp auto-refresh (updates "5m ago" -> "6m ago")
    @State private var currentTime = Date()
    
    // ✅ Emoji picker state
    @State private var showEmojiPicker = false
    
    // ✅ Photo upload state (placeholder for future implementation)
    @State private var showPhotoComingSoon = false
    
    // ✅ CRITICAL FIX: Extract short ID (first 8 chars) for Realtime Database
    // Firestore uses full UUIDs, but Realtime DB uses short IDs like "002BAE76"
    private var postId: String {
        let fullId = post.firestoreId
        // Extract first 8 characters (the short ID used in Realtime Database)
        let shortId = String(fullId.prefix(8))
        return shortId
    }
    
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
    
    // MARK: - Top Avatar Row (Premium iOS Style with Real-time Updates)
    
    private var topAvatarRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: -8) {  // Overlapping avatars for premium look
                ForEach(Array(topParticipants.enumerated()), id: \.element.id) { index, participant in
                    Button {
                        selectedUserId = participant.userId
                        showUserProfile = true
                        
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        ZStack {
                            // Avatar with premium styling - using CachedAsyncImage for faster loading
                            if let imageURL = participant.profileImageURL,
                               !imageURL.isEmpty,
                               let url = URL(string: imageURL) {
                                CachedAsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 48, height: 48)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color(.systemBackground), lineWidth: 3)
                                        )
                                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                } placeholder: {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.black, Color.black.opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 48, height: 48)
                                        .overlay(
                                            Text(participant.initials)
                                                .font(.custom("OpenSans-Bold", size: 15))
                                                .foregroundStyle(.white)
                                        )
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color(.systemBackground), lineWidth: 3)
                                        )
                                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                }
                                .id(participant.profileImageURL)  // Force refresh on URL change
                            } else {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.black, Color.black.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 48, height: 48)
                                    .overlay(
                                        Text(participant.initials)
                                            .font(.custom("OpenSans-Bold", size: 15))
                                            .foregroundStyle(.white)
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color(.systemBackground), lineWidth: 3)
                                    )
                                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            }
                            
                            // Post author indicator (only for first avatar)
                            if index == 0 {
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 16, height: 16)
                                            .overlay(
                                                Image(systemName: "pencil")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundStyle(.white)
                                            )
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(Color(.systemBackground), lineWidth: 2)
                                            )
                                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                    }
                                }
                                .frame(width: 48, height: 48)
                            }
                        }
                    }
                    .zIndex(Double(topParticipants.count - index))  // Stack properly
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: topParticipants.count)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.systemBackground),
                            Color(.systemBackground).opacity(0.95)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
    }
    
    // MARK: - Header with Avatar Row
    
    private var headerView: some View {
        VStack(spacing: 0) {
            // Avatar Row
            topAvatarRow
            
            Divider()
                .padding(.horizontal, 20)
            
            // Header with title and close button
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Comments")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.primary)
                    
                    Text("\(commentsWithReplies.count) \(commentsWithReplies.count == 1 ? "comment" : "comments")")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Premium styled close button
                Button {
                    dismiss()
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(
                            ZStack {
                                // Glass morphic background
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .opacity(0.8)
                                
                                // Subtle gradient overlay
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.15),
                                                Color.white.opacity(0.05)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                
                                // Border with gradient
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.4),
                                                Color.white.opacity(0.15)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.5
                                    )
                            }
                        )
                        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                Color(.systemBackground)
                    .overlay(
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.03),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            )
            
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
                            // P0 FIX: Skeleton loading UI - shows immediately, no blocking
                            commentsSkeletonView
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
                                                    
                                                    // Load thread summary for 10+ reply threads
                                                    if commentWithReplies.replies.count >= 10,
                                                       let commentId = commentWithReplies.comment.id,
                                                       threadSummaries[commentId] == nil {
                                                        Task {
                                                            do {
                                                                // P0 FIX: Use optional chaining for lazy-loaded service
                                                                if let summary = try await summarizationService?.getSummary(
                                                                    for: commentId,
                                                                    replies: commentWithReplies.replies
                                                                ) {
                                                                    await MainActor.run {
                                                                        threadSummaries[commentId] = summary
                                                                    }
                                                                }
                                                            } catch {
                                                                print("❌ [SUMMARY] Failed to load: \(error)")
                                                            }
                                                        }
                                                    }
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
                                            // Thread Summary (for 10+ replies)
                                            if commentWithReplies.replies.count >= 10,
                                               let commentId = commentWithReplies.comment.id {
                                                if let summary = threadSummaries[commentId] {
                                                    ThreadSummaryView(summary: summary)
                                                        .padding(.horizontal, 20)
                                                        .padding(.vertical, 12)
                                                        .transition(.move(edge: .top).combined(with: .opacity))
                                                } else if summarizationService?.isGeneratingSummary == true {
                                                    // Loading state
                                                    HStack(spacing: 12) {
                                                        ProgressView()
                                                            .tint(.secondary)
                                                        
                                                        Text("Generating thread summary...")
                                                            .font(.system(size: 13))
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    .padding(.horizontal, 20)
                                                    .padding(.vertical, 16)
                                                    .transition(.move(edge: .top).combined(with: .opacity))
                                                }
                                            }
                                            
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
                    // User avatar - Show actual profile photo with caching
                    if let imageURL = currentUserProfileImageURL,
                       !imageURL.isEmpty,
                       let url = URL(string: imageURL) {
                        CachedAsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                        } placeholder: {
                            Circle()
                                .fill(.black)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text(currentUserInitials)
                                        .font(.custom("OpenSans-SemiBold", size: 14))
                                        .foregroundStyle(.white)
                                )
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
                            .onChange(of: commentText) { _, newValue in
                                // P0 FIX: Trigger debounced tone analysis only if service loaded
                                toneGuidanceService?.analyzeText(newValue)
                            }
                        
                        // Tone guidance feedback (if present)
                        if let feedback = toneGuidanceService?.currentFeedback {
                            ToneFeedbackView(feedback: feedback) {
                                // Use suggestion
                                if let suggestion = feedback.suggestion {
                                    commentText = suggestion
                                    toneGuidanceService?.clearFeedback()
                                }
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        // Action buttons row
                        HStack(spacing: 12) {
                            // Emoji button
                            Button {
                                showEmojiPicker = true
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            } label: {
                                Image(systemName: "face.smiling")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.black.opacity(0.7))
                                    .frame(width: 24, height: 24)
                            }
                            
                            // Photo button (placeholder - feature coming soon)
                            Button {
                                showPhotoComingSoon = true
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            } label: {
                                Image(systemName: "photo")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.black.opacity(0.7))
                                    .frame(width: 24, height: 24)
                            }
                            
                            Spacer()
                            
                            // Glass Circular Send Button
                            GlassCircularButton(
                                icon: "paperplane.fill",
                                action: {
                                    submitComment()
                                },
                                isDisabled: commentText.isEmpty || isSubmittingComment
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
        .sheet(isPresented: $showEmojiPicker) {
            EmojiQuickPickerView { emoji in
                // Insert emoji at cursor position
                commentText += emoji
                showEmojiPicker = false
            }
            .presentationDetents([.height(200)])
            .presentationDragIndicator(.visible)
        }
        .alert("Photo Upload Coming Soon", isPresented: $showPhotoComingSoon) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Photo uploads in comments will be available in a future update with AI moderation.")
        }
        .task {
            print("🎬 [VIEW] CommentsView appeared for post: \(postId)")
            print("   Post firebaseId: \(post.firebaseId ?? "nil")")
            print("   Post id: \(post.id)")
            print("   Using firestoreId: \(post.firestoreId)")
            
            // P0 FIX: Lazy load AI services in background (don't block sheet appearance)
            Task(priority: .userInitiated) {
                await MainActor.run {
                    summarizationService = AIThreadSummarizationService.shared
                    toneGuidanceService = AIToneGuidanceService.shared
                    print("✅ AI services loaded in background")
                }
            }
            
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
        
        // P0-1 FIX: Prevent duplicate submissions
        guard !isSubmittingComment else {
            print("⚠️ [P0-1] Submit blocked - already submitting")
            return
        }
        
        let text = commentText
        
        print("📝 [COMMENT] Starting submission process")
        print("   Post ID: \(postId)")
        print("   Content: \(text)")
        print("   Current comments count: \(commentsWithReplies.count)")
        
        isSubmittingComment = true
        
        Task {
            // P0 FIX: Validate tone before submitting only if service loaded
            if let feedback = await toneGuidanceService?.analyzeTextImmediate(text),
               feedback.type == .flagged {
                // Block flagged content
                await MainActor.run {
                    errorMessage = feedback.message
                    showError = true
                    isSubmittingComment = false  // ✅ Re-enable button on error
                    print("🚫 [TONE] Comment blocked: \(feedback.message)")
                }
                return
            }
            
            // Clear comment text after validation passes
            await MainActor.run {
                commentText = ""
                toneGuidanceService?.clearFeedback()
                // ✅ PERFORMANCE FIX: Re-enable submit button immediately
                // This allows users to type the next comment while moderation runs in background
                isSubmittingComment = false
            }
            
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
                    // ✅ CRITICAL FIX: Pass Post object to avoid Firestore lookup
                    let newComment = try await commentService.addReply(
                        postId: postId,
                        parentCommentId: parentCommentId,
                        content: text,
                        post: self.post  // ✅ Pass Post object to bypass Firestore lookup
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
                    // ✅ CRITICAL FIX: Pass Post object to avoid Firestore lookup with short ID
                    // We pass postId (short ID) for Realtime DB operations, but also pass
                    // the full Post object to avoid needing to fetch from Firestore
                    let newComment = try await commentService.addComment(
                        postId: postId,
                        content: text,
                        post: self.post  // ✅ Pass the Post object to bypass Firestore lookup
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
                    
                    // ✅ Re-enable submit button on error
                    isSubmittingComment = false
                    
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
    
    // MARK: - Skeleton Loading UI
    
    /// P0 FIX: Skeleton loading shown immediately while comments load
    /// Provides instant visual feedback, no blocking
    private var commentsSkeletonView: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(alignment: .top, spacing: 12) {
                    // Avatar placeholder
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        // Name placeholder
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 120, height: 14)
                        
                        // Comment text placeholder (multiple lines)
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.15))
                                .frame(height: 12)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.15))
                                .frame(width: 200, height: 12)
                        }
                        
                        // Action buttons placeholder
                        HStack(spacing: 16) {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(width: 50, height: 10)
                            }
                        }
                        .padding(.top, 4)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .padding(.top, 20)
        .redacted(reason: .placeholder)  // iOS built-in shimmer effect
    }
    
    // MARK: - Real-time Updates
    
    private func startRealtimeListener() {
        guard !isListening else { return }
        
        print("🔊 CommentsView: Starting real-time listener for post: \(postId)")
        commentService.startListening(to: postId)
        isListening = true
        
        // ✅ Load initial data immediately from service cache
        Task {
            // Small delay to let listener initialize
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            await updateCommentsFromService()
            
            // Turn off loading state
            await MainActor.run {
                isLoading = false
            }
        }
        
        // ✅ VERY slow polling as safety fallback - real-time listener handles instant updates
        // Only polls every 30 seconds as a backup mechanism
        pollingTask = Task {
            while !Task.isCancelled && isListening {
                // Very slow polling (30 seconds) - real-time listener + notifications handle instant updates
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
                
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
        
        // P0-3 FIX: Stop listener for this specific post (not all listeners)
        commentService.stopListening(to: postId)
        isListening = false
    }
    
    @MainActor
    private func updateCommentsFromService() async -> Bool {
        // Get updated comments from service cache (only top-level comments)
        let allComments = commentService.comments[postId] ?? []
        
        print("📊 [UPDATE] Syncing from service for post: \(postId)")
        print("   Service has \(allComments.count) comments cached")
        
        // Build commentsWithReplies from service data
        var newCommentsWithReplies: [CommentWithReplies] = []
        
        for comment in allComments {
            guard let commentId = comment.id else {
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
            print("   ✅ Changes detected - updating UI")
            withAnimation(.easeOut(duration: 0.25)) {
                commentsWithReplies = newCommentsWithReplies
            }
            return true
        } else {
            print("   ⏭️ No changes - UI already up to date")
        }
        
        return false
    }
    
    /// Check if comments have actually changed (prevents duplicate updates)
    private func hasCommentsChanged(_ newComments: [CommentWithReplies]) -> Bool {
        // Different count = changed
        if newComments.count != commentsWithReplies.count {
            return true
        }
        
        // Check if IDs match in order
        for i in 0..<newComments.count {
            guard i < commentsWithReplies.count else {
                return true
            }
            
            let newComment = newComments[i]
            let oldComment = commentsWithReplies[i]
            
            // Different comment ID = changed
            if newComment.comment.id != oldComment.comment.id {
                return true
            }
            
            // Different reply count = changed
            if newComment.replies.count != oldComment.replies.count {
                return true
            }
            
            // Different amen count = changed
            if newComment.comment.amenCount != oldComment.comment.amenCount {
                return true
            }
            
            // Check reply IDs with bounds checking
            for j in 0..<newComment.replies.count {
                guard j < oldComment.replies.count else {
                    return true
                }
                if newComment.replies[j].id != oldComment.replies[j].id {
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
            // Avatar - Tappable to view profile with cached image loading
            Button {
                onProfileTap()
                
                // Haptic feedback
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
            } label: {
                if let imageURL = comment.authorProfileImageURL,
                   !imageURL.isEmpty,
                   let url = URL(string: imageURL) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: isReply ? 28 : 36, height: isReply ? 28 : 36)
                            .clipShape(Circle())
                    } placeholder: {
                        Circle()
                            .fill(.black)
                            .frame(width: isReply ? 28 : 36, height: isReply ? 28 : 36)
                            .overlay(
                                Text(comment.authorInitials)
                                    .font(.custom("OpenSans-SemiBold", size: isReply ? 10 : 12))
                                    .foregroundStyle(.white)
                            )
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
                
                // Content with link detection
                LinkedText(comment.content, fontSize: isReply ? 13 : 14)
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
}

// MARK: - Participant Info Model

struct ParticipantInfo: Identifiable {
    let id = UUID()
    let userId: String
    let initials: String
    let profileImageURL: String?
    let score: Double
}

// MARK: - Linked Text View

struct LinkedText: View {
    let text: String
    let fontSize: CGFloat
    
    init(_ text: String, fontSize: CGFloat = 14) {
        self.text = text
        self.fontSize = fontSize
    }
    
    var body: some View {
        Text(attributedString)
            .font(.custom("OpenSans-Regular", size: fontSize))
    }
    
    private var attributedString: AttributedString {
        var attributedString = AttributedString(text)
        attributedString.foregroundColor = .black
        
        // Detect URLs using NSDataDetector
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let nsString = text as NSString
        let matches = detector?.matches(in: text, range: NSRange(location: 0, length: nsString.length)) ?? []
        
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let attributedRange = AttributedString.Index(range.lowerBound, within: attributedString)!
                ..< AttributedString.Index(range.upperBound, within: attributedString)!
            
            // Make link blue and underlined
            attributedString[attributedRange].foregroundColor = .blue
            attributedString[attributedRange].underlineStyle = .single
            
            // Add URL for tapping
            if let url = match.url {
                attributedString[attributedRange].link = url
            }
        }
        
        return attributedString
    }
}

// MARK: - Emoji Quick Picker

struct EmojiQuickPickerView: View {
    let onSelect: (String) -> Void
    
    // 5 quick reaction emojis commonly used in faith discussions
    let quickEmojis = ["🙏", "❤️", "🔥", "✨", "💯"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Quick Reactions")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            
            // Emoji buttons
            HStack(spacing: 16) {
                ForEach(quickEmojis, id: \.self) { emoji in
                    Button {
                        onSelect(emoji)
                        
                        // Haptic feedback
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        Text(emoji)
                            .font(.system(size: 40))
                            .frame(width: 60, height: 60)
                            .background(
                                ZStack {
                                    // Glass morphic background
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.8)
                                    
                                    // Subtle gradient overlay
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.15),
                                                    Color.white.opacity(0.05)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    
                                    // Border with gradient
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.4),
                                                    Color.white.opacity(0.15)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 0.5
                                        )
                                }
                            )
                            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(EmojiButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
    }
}

// Custom button style for emoji buttons with smooth press animation
struct EmojiButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
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
