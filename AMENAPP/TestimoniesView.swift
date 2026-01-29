//
//  TestimoniesView.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//

import SwiftUI
import FirebaseAuth

struct TestimoniesView: View {
    @StateObject private var postsManager = PostsManager.shared
    @State private var selectedFilter: TestimonyFilter = .all
    @State private var selectedCategory: TestimonyCategory? = nil
    @State private var isCategoryBrowseExpanded = false
    @State private var isLoadingPosts = false
    @State private var showEditSheet = false
    @State private var editingPost: Post? = nil
    @State private var editedContent = ""
    
    enum TestimonyFilter: String, CaseIterable {
        case all = "All"
        case recent = "Recent"
        case popular = "Popular"
        case following = "Following"
    }
    
    // Computed property to get filtered posts from PostsManager
    var filteredPosts: [Post] {
        var posts = postsManager.testimoniesPosts
        
        // Apply category filter if selected
        if let category = selectedCategory {
            posts = posts.filter { post in
                post.topicTag?.lowercased() == category.title.lowercased()
            }
        }
        
        // Apply sorting based on filter (client-side to ensure consistency)
        switch selectedFilter {
        case .all, .recent:
            // Already sorted by timestamp in PostsManager
            break
        case .popular:
            posts.sort { $0.amenCount + $0.commentCount > $1.amenCount + $1.commentCount }
        case .following:
            // TODO: Filter by following status when implemented
            // For now, show all posts
            break
        }
        
        return posts
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share your testimony, encourage others")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text("Testimonies")
                            .font(.custom("OpenSans-Bold", size: 24))
                            .foregroundStyle(.black)
                        
                        Spacer()
                        
                        // Loading indicator
                        if isLoadingPosts {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        
                        // Clear category filter if selected
                        if selectedCategory != nil {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedCategory = nil
                                    // Don't refetch - computed property will handle filtering
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Clear filter")
                                        .font(.custom("OpenSans-SemiBold", size: 12))
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                }
                                .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                
                // Show selected category or default text
                if let category = selectedCategory {
                    HStack(spacing: 6) {
                        Image(systemName: category.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(category.color)
                        
                        Text(category.title)
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(category.color)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(category.backgroundColor)
                    )
                } else {
                    Text("Healing • Career • Faith • Family")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            
            // Filters - Center Aligned
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    ForEach(TestimonyFilter.allCases, id: \.self) { filter in
                        Button {
                            withAnimation {
                                selectedFilter = filter
                                // Don't refetch - just rely on computed property filtering
                                // This keeps newly created posts visible
                            }
                        } label: {
                            Text(filter.rawValue)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(selectedFilter == filter ? .white : .black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(selectedFilter == filter ? Color.black : Color.gray.opacity(0.1))
                                )
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
            
            // Collapsible Categories Section
            VStack(alignment: .leading, spacing: 12) {
                // Category Header Button
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isCategoryBrowseExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text("Browse by Category")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.black)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isCategoryBrowseExpanded ? 180 : 0))
                    }
                    .padding(.horizontal)
                }
                
                // Expandable Category Grid
                if isCategoryBrowseExpanded {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        TestimonyCategoryCard(category: .healing, isSelected: selectedCategory?.title == TestimonyCategory.healing.title) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedCategory = .healing
                                isCategoryBrowseExpanded = false
                                // Don't refetch - computed property handles filtering
                            }
                        }
                        TestimonyCategoryCard(category: .career, isSelected: selectedCategory?.title == TestimonyCategory.career.title) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedCategory = .career
                                isCategoryBrowseExpanded = false
                                // Don't refetch - computed property handles filtering
                            }
                        }
                        TestimonyCategoryCard(category: .relationship, isSelected: selectedCategory?.title == TestimonyCategory.relationship.title) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedCategory = .relationship
                                isCategoryBrowseExpanded = false
                                // Don't refetch - computed property handles filtering
                            }
                        }
                        TestimonyCategoryCard(category: .financial, isSelected: selectedCategory?.title == TestimonyCategory.financial.title) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedCategory = .financial
                                isCategoryBrowseExpanded = false
                                // Don't refetch - computed property handles filtering
                            }
                        }
                        TestimonyCategoryCard(category: .spiritual, isSelected: selectedCategory?.title == TestimonyCategory.spiritual.title) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedCategory = .spiritual
                                isCategoryBrowseExpanded = false
                                // Don't refetch - computed property handles filtering
                            }
                        }
                        TestimonyCategoryCard(category: .family, isSelected: selectedCategory?.title == TestimonyCategory.family.title) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedCategory = .family
                                isCategoryBrowseExpanded = false
                                // Don't refetch - computed property handles filtering
                            }
                        }
                    }
                    .padding(.horizontal)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                }
            }
            
            // Filtered testimonies feed
            VStack(spacing: 16) {
                ForEach(filteredPosts) { post in
                    PostCard(
                        post: post,
                        isUserPost: post.authorId == Auth.auth().currentUser?.uid
                    )
                }
                
                // Show empty state if no posts
                if filteredPosts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "hands.sparkles")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        
                        if selectedCategory != nil {
                            Text("No testimonies in this category")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.primary)
                            
                            Text("Be the first to share your story!")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No testimonies yet")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.primary)
                            
                            Text("Share how God is working in your life!")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                }
            }
            .padding(.horizontal)
        }
        .refreshable {
            await refreshTestimonies()
        }
        .task {
            // Initial fetch when view appears - only fetch once
            if postsManager.testimoniesPosts.isEmpty {
                fetchPosts()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newPostCreated)) { notification in
            // Refresh when new post is created
            if let userInfo = notification.userInfo,
               let category = userInfo["category"] as? String,
               category == Post.PostCategory.testimonies.rawValue {
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                // The new post is already in postsManager.testimoniesPosts
                // No need to refetch - the computed property will show it
                print("✅ New testimony post received - already visible in feed")
            }
        }
    }
    
    // MARK: - Helper Functions
    
    /// Refresh testimonies with pull-to-refresh
    private func refreshTestimonies() async {
        isLoadingPosts = true
        print("🔄 Refreshing Testimonies posts...")
        
        await postsManager.fetchFilteredPosts(
            for: .testimonies,
            filter: selectedFilter.rawValue.lowercased(),
            topicTag: selectedCategory?.title
        )
        
        // Haptic feedback on completion
        await MainActor.run {
            isLoadingPosts = false
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            print("✅ Testimonies posts refreshed!")
        }
    }
    
    /// Fetch posts from backend with current filters applied
    private func fetchPosts() {
        // Don't show loading for filter changes to avoid flickering
        // Only show loading on initial load
        if postsManager.testimoniesPosts.isEmpty {
            isLoadingPosts = true
        }
        
        Task {
            await postsManager.fetchFilteredPosts(
                for: .testimonies,
                filter: selectedFilter.rawValue.lowercased(),
                topicTag: selectedCategory?.title
            )
            
            await MainActor.run {
                isLoadingPosts = false
            }
        }
    }
    
    private func deletePost(_ post: Post) {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.warning)
        
        // In a real app, delete from backend
        print("🗑️ Deleting post: \(post.id)")
        
        // TODO: Remove from data source
        // postsManager.deletePost(post.id)
    }
    
    private func editPost(_ post: Post) {
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        // In a real app, show edit sheet
        print("✏️ Editing post: \(post.id)")
        
        // TODO: Show edit interface
        // showEditPost = true
        // editingPost = post
    }
    
    private func repostPost(_ post: Post) {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        // Add to user's reposts
        print("🔄 Reposted: \(post.content)")
        
        // TODO: Add to reposts collection
        // postsManager.addRepost(post)
    }
}

// MARK: - Testimony Feed Comment Model (for UI)

struct TestimonyFeedComment: Identifiable {
    let id: String
    let authorName: String
    let authorInitials: String
    let timeAgo: String
    let content: String
    let amenCount: Int
}

// MARK: - Comment Extensions for Testimonies

extension Comment {
    /// Convert to TestimonyFeedComment for UI compatibility
    func toTestimonyFeedComment() -> TestimonyFeedComment {
        TestimonyFeedComment(
            id: id ?? UUID().uuidString,
            authorName: authorName,
            authorInitials: authorInitials,
            timeAgo: timeAgo,
            content: content,
            amenCount: amenCount
        )
    }
}

// MARK: - Testimony Post Model

struct TestimonyPost: Identifiable {
    let id = UUID()
    let authorName: String
    let authorInitials: String
    let timeAgo: String
    let timestamp: Date
    let content: String
    let category: String
    let amens: Int
    let prayers: Int
    let comments: Int
    let isFromFollowing: Bool
    let isOwnPost: Bool // True if current user is author
    var isReposted: Bool = false
}

// MARK: - Sample Testimonies Data

// Sample testimonies removed - using real data from Firebase via PostsManager
private let sampleTestimonies: [TestimonyPost] = []


struct TestimonyCategoryCard: View {
    let category: TestimonyCategory
    let isSelected: Bool
    let action: () -> Void
    @State private var showCategoryDetail = false
    
    var body: some View {
        Button {
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: category.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(category.color)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(category.color)
                    }
                }
                
                Text(category.title)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
                
                Text(category.subtitle)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? category.backgroundColor.opacity(0.3) : category.backgroundColor)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? category.color : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Testimony Post Card with Edit/Delete

struct TestimonyPostCard: View {
    let post: Post
    let onDelete: () -> Void
    let onEdit: () -> Void
    let onRepost: () -> Void
    
    @State private var showActionMenu = false
    @State private var showDeleteConfirmation = false
    @State private var showComments = false
    @State private var showFullCommentSheet = false
    @State private var showShareSheet = false
    @State private var hasAmened = false
    @State private var hasSaved = false
    @State private var hasReposted = false
    @State private var amenCount: Int
    @State private var commentCount: Int
    @State private var repostCount: Int
    @State private var showReportSheet = false
    
    // Helper properties to determine if this is the user's own post
    private var isOwnPost: Bool {
        // Check against current user's Firebase Auth ID
        guard let currentUserId = FirebaseManager.shared.currentUser?.uid else {
            return false
        }
        return post.authorId == currentUserId
    }
    
    init(post: Post, onDelete: @escaping () -> Void, onEdit: @escaping () -> Void, onRepost: @escaping () -> Void) {
        self.post = post
        self.onDelete = onDelete
        self.onEdit = onEdit
        self.onRepost = onRepost
        _amenCount = State(initialValue: post.amenCount)
        _commentCount = State(initialValue: post.commentCount)
        _repostCount = State(initialValue: post.repostCount)
        _hasReposted = State(initialValue: post.isRepost)
    }
    
    @State private var isFollowing = false
    
    // MARK: - Computed Properties
    
    private var shareItems: [Any] {
        let shareText = """
        📖 Testimony from \(post.authorName)
        
        \(post.content)
        
        Join us on AMEN APP to share and read more testimonies!
        https://amenapp.com/testimony/\(post.id.uuidString)
        """
        return [shareText]
    }
    
    private var avatarView: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(Color.black)
                .frame(width: 44, height: 44)
            
            Text(post.authorInitials)
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(.white)
            
            // Follow button - only show if not user's post
            if !isOwnPost {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isFollowing.toggle()
                    }
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                } label: {
                    Image(systemName: isFollowing ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isFollowing ? .black : .white)
                        .background(
                            Circle()
                                .fill(isFollowing ? Color.white : Color.black)
                                .frame(width: 18, height: 18)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.15), lineWidth: isFollowing ? 1 : 0)
                        )
                }
                .symbolEffect(.bounce, value: isFollowing)
                .offset(x: 2, y: 2)
            }
        }
    }
    
    private var authorInfoView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(post.authorName)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
                
                // Category badge
                if let topicTag = post.topicTag,
                   let category = [TestimonyCategory.healing, .career, .relationship, .financial, .spiritual, .family].first(where: { $0.title.lowercased() == topicTag.lowercased() }) {
                    HStack(spacing: 3) {
                        Image(systemName: category.icon)
                            .font(.system(size: 9, weight: .semibold))
                        Text(category.title)
                            .font(.custom("OpenSans-Bold", size: 10))
                    }
                    .foregroundStyle(category.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(category.backgroundColor)
                    )
                }
            }
            
            Text(post.timeAgo)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)
        }
    }
    
    private var menuView: some View {
        Menu {
            if isOwnPost {
                Button {
                    onEdit()
                } label: {
                    Label("Edit Post", systemImage: "pencil")
                }
                
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Post", systemImage: "trash")
                }
                
                Divider()
            }
            
            Button {
                onRepost()
            } label: {
                Label(post.isRepost ? "Remove Repost" : "Repost", systemImage: "arrow.2.squarepath")
            }
            
            Button {
                hasSaved.toggle()
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
            } label: {
                Label(hasSaved ? "Unsave" : "Save", systemImage: hasSaved ? "bookmark.fill" : "bookmark")
            }
            
            Button {
                sharePost()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            
            Button {
                copyLink()
            } label: {
                Label("Copy Link", systemImage: "link")
            }
            
            if !isOwnPost {
                Divider()
                
                Button(role: .destructive) {
                    showReportSheet = true
                } label: {
                    Label("Report Post", systemImage: "exclamationmark.triangle")
                }
                
                Button(role: .destructive) {
                    muteAuthor()
                } label: {
                    Label("Mute \(post.authorName)", systemImage: "speaker.slash")
                }
                
                Button(role: .destructive) {
                    blockAuthor()
                } label: {
                    Label("Block \(post.authorName)", systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.6))
                .frame(width: 32, height: 32)
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 12) {
            avatarView
            authorInfoView
            Spacer()
            menuView
        }
    }
    
    private var engagementActionsView: some View {
        HStack(spacing: 8) {
            amenButton
            commentButton
            repostButton
            Spacer()
            shareButton
        }
    }
    
    private var amenButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                hasAmened.toggle()
                amenCount += hasAmened ? 1 : -1
            }
            let haptic = UIImpactFeedbackGenerator(style: hasAmened ? .medium : .light)
            haptic.impactOccurred()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: hasAmened ? "hands.clap.fill" : "hands.clap")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(amenCount)")
                    .font(.custom("OpenSans-SemiBold", size: 11))
            }
            .foregroundStyle(hasAmened ? Color.black : Color.black.opacity(0.5))
            .contentTransition(.numericText())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(hasAmened ? Color.white : Color.black.opacity(0.05))
                    .shadow(color: hasAmened ? Color.black.opacity(0.15) : Color.clear, radius: 8, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(hasAmened ? Color.black.opacity(0.2) : Color.black.opacity(0.1), lineWidth: hasAmened ? 1.5 : 1)
            )
        }
    }
    
    private var commentButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showFullCommentSheet = true
            }
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(commentCount)")
                    .font(.custom("OpenSans-SemiBold", size: 11))
            }
            .foregroundStyle(Color.black.opacity(0.5))
            .contentTransition(.numericText())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    private var repostButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                hasReposted.toggle()
                repostCount += hasReposted ? 1 : -1
            }
            onRepost()
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: hasReposted ? "arrow.2.squarepath.circle.fill" : "arrow.2.squarepath")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(repostCount)")
                    .font(.custom("OpenSans-SemiBold", size: 11))
            }
            .foregroundStyle(hasReposted ? Color.green : Color.black.opacity(0.5))
            .contentTransition(.numericText())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(hasReposted ? Color.green.opacity(0.1) : Color.black.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .stroke(hasReposted ? Color.green.opacity(0.3) : Color.black.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    private var shareButton: some View {
        Button {
            sharePost()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.05))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            headerView
            
            // Content
            Text(post.content)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.primary)
                .lineSpacing(4)
            
            // Engagement Actions - Prayer UI Style
            engagementActionsView
            
            // Comment Section - Inline Preview (showing first comment only)
            if showComments {
                TestimonyCommentSection(
                    post: post,
                    commentCount: $commentCount,
                    showPreviewOnly: true,
                    onExpandComments: {
                        showFullCommentSheet = true
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .sheet(isPresented: $showFullCommentSheet) {
            TestimonyFullCommentSheet(
                post: post,
                commentCount: $commentCount
            )
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .confirmationDialog("Delete this testimony?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showReportSheet) {
            ReportPostSheet(post: post, postAuthor: post.authorName, category: .testimonies)
        }
    }
    
    // MARK: - Helper Functions
    
    private func sharePost() {
        showShareSheet = true
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func copyLink() {
        UIPasteboard.general.string = "https://amenapp.com/testimony/\(post.id.uuidString)"
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        print("🔗 Link copied to clipboard")
    }
    
    private func muteAuthor() {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        print("🔇 Muted \(post.authorName)")
        // TODO: Add to muted users list
    }
    
    private func blockAuthor() {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.warning)
        print("🚫 Blocked \(post.authorName)")
        // TODO: Add to blocked users list
    }
}

// MARK: - Testimony Comment Section

struct TestimonyCommentSection: View {
    let post: Post  // Changed from testimonyAuthor to full post
    @Binding var commentCount: Int
    var showPreviewOnly: Bool = false
    var onExpandComments: (() -> Void)? = nil
    
    @State private var commentText = ""
    @State private var showQuickResponses = false
    @FocusState private var isCommentFocused: Bool
    
    // Real comments - loaded from backend
    @State private var comments: [TestimonyFeedComment] = []
    @State private var isLoading = false
    
    private let commentService = CommentService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .padding(.vertical, 4)
            
            // Comments header
            HStack {
                Text("Comments")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.black.opacity(0.9))
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Text("\(commentCount)")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.black.opacity(0.5))
                }
                
                if showPreviewOnly && comments.count > 1 {
                    Button {
                        onExpandComments?()
                    } label: {
                        Text("View all")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            // Quick response suggestions
            if showQuickResponses && !showPreviewOnly {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickResponses, id: \.self) { response in
                            Button {
                                commentText = response
                                isCommentFocused = true
                            } label: {
                                Text(response)
                                    .font(.custom("OpenSans-SemiBold", size: 12))
                                    .foregroundStyle(.black.opacity(0.7))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.05))
                                            .overlay(
                                                Capsule()
                                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                                            )
                                    )
                            }
                        }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            if !showPreviewOnly {
                // Comment input
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text("ME")
                                .font(.custom("OpenSans-Bold", size: 11))
                                .foregroundStyle(.white)
                        )
                    
                    HStack {
                        TextField("Add an encouraging comment...", text: $commentText)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .focused($isCommentFocused)
                        
                        if !commentText.isEmpty {
                            Button {
                                postComment()
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.black)
                            }
                        } else {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showQuickResponses.toggle()
                                }
                            } label: {
                                Image(systemName: showQuickResponses ? "sparkles.square.filled.on.square" : "sparkles")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.black.opacity(0.5))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.05))
                    )
                }
            }
            
            // Comments list
            VStack(alignment: .leading, spacing: 12) {
                let displayComments = showPreviewOnly ? Array(comments.prefix(1)) : comments
                ForEach(displayComments, id: \.id) { comment in
                    TestimonyCommentRow(
                        comment: comment,
                        commentId: comment.id,
                        postId: post.id.uuidString
                    )
                }
            }
        }
        .padding(.top, 8)
        .task {
            // Load comments when view appears
            await loadComments()
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadComments() async {
        isLoading = true
        
        do {
            let fetchedComments = try await commentService.fetchComments(for: post.id.uuidString)
            
            await MainActor.run {
                comments = fetchedComments.map { $0.toTestimonyFeedComment() }
                isLoading = false
            }
        } catch {
            print("❌ Error loading comments: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    var quickResponses: [String] {
        [
            "Amen! 🙏",
            "So encouraging!",
            "Praise God! 🙌",
            "Thank you for sharing!",
            "God is faithful! ✨",
            "This blessed me!"
        ]
    }
    
    private func postComment() {
        guard !commentText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        let newComment = TestimonyFeedComment(
            id: UUID().uuidString,
            authorName: "You",
            authorInitials: "ME",
            timeAgo: "Just now",
            content: commentText,
            amenCount: 0
        )
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            comments.insert(newComment, at: 0)
            commentCount += 1
            commentText = ""
        }
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
}

// MARK: - Testimony Comment Row

struct TestimonyCommentRow: View {
    let comment: TestimonyFeedComment
    let commentId: String
    let postId: String
    @State private var hasAmened = false
    @State private var amenCount: Int
    
    init(comment: TestimonyFeedComment, commentId: String, postId: String) {
        self.comment = comment
        self.commentId = commentId
        self.postId = postId
        _amenCount = State(initialValue: comment.amenCount)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.black.opacity(0.1))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(String(comment.authorName.prefix(1)))
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundStyle(.black.opacity(0.7))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundStyle(.black.opacity(0.9))
                    
                    Text(comment.timeAgo)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.black.opacity(0.4))
                }
                
                Text(comment.content)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.black.opacity(0.8))
                    .lineSpacing(2)
                
                // Comment actions
                HStack(spacing: 16) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            hasAmened.toggle()
                            amenCount += hasAmened ? 1 : -1
                        }
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: hasAmened ? "hands.clap.fill" : "hands.clap")
                                .font(.system(size: 11, weight: .semibold))
                            if amenCount > 0 {
                                Text("\(amenCount)")
                                    .font(.custom("OpenSans-SemiBold", size: 10))
                            }
                        }
                        .foregroundStyle(hasAmened ? .black : .black.opacity(0.5))
                    }
                    
                    Button {
                        // Reply to comment
                    } label: {
                        Text("Reply")
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(.black.opacity(0.5))
                    }
                }
                .padding(.top, 4)
            }
            
            Spacer()
        }
    }
}

// MARK: - Inline Category Detail View (to avoid conflicts)

struct TestimonyCategoryDetailInlineView: View {
    @Environment(\.dismiss) private var dismiss
    let category: TestimonyCategory
    @State private var selectedFilter: CategoryFilter = .recent
    
    enum CategoryFilter: String, CaseIterable {
        case recent = "Recent"
        case popular = "Popular"
        case encouraging = "Most Encouraging"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(category.backgroundColor)
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: category.icon)
                                    .font(.system(size: 40))
                                    .foregroundStyle(category.color)
                            }
                            
                            Spacer()
                        }
                        
                        Text(category.title)
                            .font(.custom("OpenSans-Bold", size: 32))
                            .foregroundStyle(.primary)
                        
                        Text(categoryDescription)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Filter Tabs - Center Aligned
                    HStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(CategoryFilter.allCases, id: \.self) { filter in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedFilter = filter
                                    }
                                } label: {
                                    Text(filter.rawValue)
                                        .font(.custom("OpenSans-SemiBold", size: 13))
                                        .foregroundStyle(selectedFilter == filter ? .white : .black)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(selectedFilter == filter ? category.color : Color.gray.opacity(0.1))
                                        )
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    // Testimonies Feed
                    VStack(spacing: 16) {
                        ForEach(testimonyPosts, id: \.content) { post in
                            PostCard(
                                authorName: post.authorName,
                                timeAgo: post.timeAgo,
                                content: post.content,
                                category: .testimonies
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Share category
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
    
    var categoryDescription: String {
        switch category.title {
        case "Healing":
            return "Stories of God's healing power - physical, emotional, and spiritual restoration."
        case "Career":
            return "Testimonies of God's provision and guidance in work and career."
        case "Relationships":
            return "Stories of restored marriages, healed friendships, and divine connections."
        case "Financial":
            return "Testimonies of God's supernatural provision and financial breakthrough."
        case "Spiritual Growth":
            return "Stories of deeper faith, breakthrough moments, and spiritual transformation."
        case "Family":
            return "Testimonies of God's faithfulness in family situations."
        default:
            return "Share your story and encourage others in their faith journey."
        }
    }
    
    var testimonyPosts: [(authorName: String, timeAgo: String, content: String)] {
        switch category.title {
        case "Healing":
            return [
                ("Grace Thompson", "4h", "After 2 years of chronic pain, I'm completely healed! 🙏✨"),
                ("Daniel Park", "8h", "My daughter's cancer is in complete remission. God is faithful! 💙")
            ]
        case "Career":
            return [
                ("Sarah Mitchell", "3h", "Just got promoted to a position I wasn't even qualified for! 🚪✨"),
                ("Marcus Lee", "6h", "Started my own business - now making 3x my previous salary! 💼")
            ]
        case "Relationships":
            return [
                ("Emily Foster", "5h", "My marriage was headed for divorce. God has completely restored it! 💑"),
                ("Michael Chen", "7h", "Reconciled with my father after 10 years! 👨‍👦")
            ]
        case "Financial":
            return [
                ("Patricia Moore", "2h", "Received an unexpected check that covered my entire rent! 💰"),
                ("George Thompson", "9h", "Paid off $50,000 in debt in 18 months! 🎉")
            ]
        case "Spiritual Growth":
            return [
                ("Olivia Chen", "6h", "Experiencing God's presence like never before! 🔥"),
                ("Nathan Parker", "9h", "God gave me a breakthrough in understanding scripture! 📖✨")
            ]
        case "Family":
            return [
                ("Hannah Davis", "4h", "My son rededicated his life to Christ! 🙏"),
                ("Jacob Williams", "8h", "God blessed us with a baby after 7 years! 👶")
            ]
        default:
            return [("John Smith", "1h", "God is faithful in every season! 🙏")]
        }
    }
}

// MARK: - Full Comment Sheet

struct TestimonyFullCommentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let post: Post
    @Binding var commentCount: Int
    
    @State private var commentText = ""
    @State private var showQuickResponses = false
    @State private var isLoading = true
    @FocusState private var isCommentFocused: Bool
    @StateObject private var commentService = CommentService.shared
    
    @State private var comments: [TestimonyFeedComment] = []
    
    // MARK: - Computed Views
    
    private var commentInputRow: some View {
        HStack(spacing: 12) {
            userAvatar
            inputField
        }
    }
    
    private var userAvatar: some View {
        Circle()
            .fill(Color.black)
            .frame(width: 36, height: 36)
            .overlay(
                Text("ME")
                    .font(.custom("OpenSans-Bold", size: 12))
                    .foregroundStyle(.white)
            )
    }
    
    private var inputField: some View {
        HStack {
            TextField("Add an encouraging comment...", text: $commentText)
                .font(.custom("OpenSans-Regular", size: 14))
                .focused($isCommentFocused)
            
            inputActionButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.05))
        )
    }
    
    @ViewBuilder
    private var inputActionButton: some View {
        if !commentText.isEmpty {
            Button {
                postComment()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.black)
            }
        } else {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showQuickResponses.toggle()
                }
            } label: {
                Image(systemName: showQuickResponses ? "sparkles.square.filled.on.square" : "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(.black.opacity(0.5))
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Post Header (condensed)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 40, height: 40)
                            
                            Text(post.authorInitials)
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(post.authorName)
                                    .font(.custom("OpenSans-Bold", size: 14))
                                    .foregroundStyle(.primary)
                                
                                // Category badge
                                if let topicTag = post.topicTag,
                                   let category = [TestimonyCategory.healing, .career, .relationship, .financial, .spiritual, .family].first(where: { $0.title.lowercased() == topicTag.lowercased() }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: category.icon)
                                            .font(.system(size: 8, weight: .semibold))
                                        Text(category.title)
                                            .font(.custom("OpenSans-Bold", size: 9))
                                    }
                                    .foregroundStyle(category.color)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(category.backgroundColor)
                                    )
                                }
                            }
                            
                            Text(post.timeAgo)
                                .font(.custom("OpenSans-Regular", size: 11))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    // Post content
                    Text(post.content)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                        .lineLimit(3)
                }
                .padding()
                .background(Color(.systemBackground))
                
                Divider()
                
                // Comments List
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Comments header
                        HStack {
                            Text("Comments")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.black.opacity(0.9))
                            
                            Spacer()
                            
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text("\(commentCount)")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.black.opacity(0.5))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        
                        // Quick response suggestions
                        if showQuickResponses {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(quickResponses, id: \.self) { response in
                                        Button {
                                            commentText = response
                                            isCommentFocused = true
                                        } label: {
                                            Text(response)
                                                .font(.custom("OpenSans-SemiBold", size: 12))
                                                .foregroundStyle(.black.opacity(0.7))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(
                                                    Capsule()
                                                        .fill(Color.black.opacity(0.05))
                                                        .overlay(
                                                            Capsule()
                                                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                                                        )
                                                )
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        // Comments or empty state
                        if isLoading {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Loading comments...")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else if comments.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.secondary)
                                
                                Text("No comments yet")
                                    .font(.custom("OpenSans-Bold", size: 18))
                                    .foregroundStyle(.primary)
                                
                                Text("Be the first to comment!")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            // Comments
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(comments) { comment in
                                    TestimonyCommentRow(
                                        comment: comment,
                                        commentId: comment.id,
                                        postId: post.id.uuidString
                                    )
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                }
                
                // Comment Input (sticky at bottom)
                VStack(spacing: 0) {
                    Divider()
                    
                    commentInputRow
                        .padding()
                        .background(Color(.systemBackground))
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.gray)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .task {
                await loadComments()
            }
        }
    }
    
    // MARK: - Load Comments
    
    private func loadComments() async {
        isLoading = true
        
        do {
            let fetchedComments = try await commentService.fetchComments(for: post.id.uuidString)
            
            await MainActor.run {
                comments = fetchedComments.map { $0.toTestimonyFeedComment() }
                isLoading = false
            }
        } catch {
            print("❌ Failed to load comments: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    var quickResponses: [String] {
        [
            "Amen! 🙏",
            "So encouraging!",
            "Praise God! 🙌",
            "Thank you for sharing!",
            "God is faithful! ✨",
            "This blessed me!"
        ]
    }
    
    private func postComment() {
        guard !commentText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        Task {
            do {
                let newComment = try await commentService.addComment(
                    postId: post.id.uuidString,
                    content: commentText
                )
                
                await MainActor.run {
                    // Convert to TestimonyFeedComment and add to list
                    comments.insert(newComment.toTestimonyFeedComment(), at: 0)
                    commentCount += 1
                    commentText = ""
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                print("❌ Failed to post comment: \(error)")
            }
        }
    }
}


#Preview {
    TestimoniesView()
}
