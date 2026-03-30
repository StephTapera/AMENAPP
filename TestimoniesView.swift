//
//  TestimoniesView.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct TestimoniesView: View {
    @ObservedObject private var postsManager = PostsManager.shared
    @ObservedObject private var testimonyAlgorithm = TestimoniesAlgorithm.shared
    @State private var selectedFilter: TestimonyFilter = .all
    @State private var selectedCategory: TestimonyCategory? = nil
    @State private var isCategoryBrowseExpanded = false
    @State private var isLoadingPosts = false
    @State private var showEditSheet = false
    @State private var editingPost: Post? = nil
    @State private var editedContent = ""
    @State private var currentToast: Toast? = nil
    @State private var errorMessage: String? = nil
    @State private var isInitialLoad = true
    @State private var personalizedPosts: [Post] = []
    @State private var hasPersonalized = false
    @State private var scrollViewDelegate: ScrollViewDelegateHandler?
    @State private var showHeader = true
    
    // MARK: - Pagination State
    @State private var visiblePostCount = 20
    @State private var isLoadingMore = false
    
    @Environment(\.tabBarVisible) private var tabBarVisible
    
    // Animation timing constants
    private let fastAnimationDuration: Double = 0.12
    private let standardAnimationDuration: Double = 0.2
    private let springResponse: Double = 0.3
    private let springDamping: Double = 0.7
    private let filterHaptic = UIImpactFeedbackGenerator(style: .light)
    
    enum TestimonyFilter: String, CaseIterable {
        case all = "All"
        case recent = "Recent"
        case popular = "Popular"
        case following = "Following"
    }
    
    // ✅ Use PostsManager for consistent data source with intelligent algorithm
    var filteredPosts: [Post] {
        var posts = postsManager.testimoniesPosts

        // Apply category filter if selected.
        // Match loosely: "Relationships" matches topicTag "relationship", "relationships", etc.
        if let category = selectedCategory {
            let titleLower = category.title.lowercased()
            posts = posts.filter { post in
                guard let tag = post.topicTag?.lowercased() else { return false }
                return tag == titleLower
                    || titleLower.hasPrefix(tag)
                    || tag.hasPrefix(titleLower)
            }
        }

        // Apply sorting based on filter
        switch selectedFilter {
        case .all:
            // Use personalized ranking if available
            posts = hasPersonalized && !personalizedPosts.isEmpty ? personalizedPosts : posts
        case .recent:
            // Already sorted by timestamp in RealtimePostService
            break
        case .popular:
            // Intelligent popularity scoring (not just sum)
            posts = testimonyAlgorithm.rankTestimonies(posts, for: testimonyAlgorithm.userPreferences)
        case .following:
            // Filter to posts from users the current user follows
            let followingSet = FollowService.shared.following
            if !followingSet.isEmpty {
                posts = posts.filter { followingSet.contains($0.authorId) }
            } else {
                // No following data yet — show empty (not all posts)
                posts = []
            }
        }

        return posts
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
                // Header
                if showHeader {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Share your testimony, encourage others")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("#Testimonies")
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
                                    selectedCategory = nil
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("Clear filter")
                                            .font(.custom("OpenSans-SemiBold", size: 12))
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                    }
                                    .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                                .animation(.easeOut(duration: fastAnimationDuration), value: selectedCategory)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Error banner (if any)
                if let errorMessage = errorMessage {
                    InlineErrorBanner(message: errorMessage) {
                        Task { await refreshTestimonies() }
                    }
                }

                // Loading state - show skeletons on initial load
                if isInitialLoad && isLoadingPosts {
                    PostListSkeletonView(count: 3)
                } else if !isLoadingPosts && filteredPosts.isEmpty && selectedFilter != .following {
                    // Only show full empty state for non-Following tabs when there's truly no data.
                    // For the Following tab, contentView handles its own empty state so filter
                    // buttons remain visible even when the user isn't following anyone yet.
                    EmptyPostsView(category: "testimonies")
                        .padding(.top, 40)
                } else {
                    contentView
                }
        }
        .toast($currentToast)
        .sheet(isPresented: $showEditSheet, onDismiss: { editingPost = nil }) {
            if let post = editingPost {
                EditPostSheet(post: post)
            }
        }
        .task {
            if isInitialLoad {
                await loadInitialTestimonies()
            }
            if !hasPersonalized {
                testimonyAlgorithm.loadPreferences()
                personalizeTestimoniesFeed()
                hasPersonalized = true
            }
            // Keep listener alive across tab switches — only starts if not already active
            FirebasePostService.shared.startListening(category: .testimonies)
        }
        .onAppear {
            filterHaptic.prepare()
            // Only fetch if we have no posts yet — prevents redundant Firestore fetch on every tab switch
            if postsManager.testimoniesPosts.isEmpty && !isLoadingPosts {
                fetchPosts()
            }
            // Only personalize if preferences have already been loaded (hasPersonalized gate prevents
            // a redundant re-rank on every re-appear before the .task personalization runs)
            if hasPersonalized {
                personalizeTestimoniesFeed()
            }
        }
        .onDisappear {
            // Don't stop the listener — keep it alive so real-time updates arrive while on other tabs
        }
        .onChange(of: postsManager.testimoniesPosts) { oldValue, newValue in
            if oldValue.count != newValue.count {
                personalizeTestimoniesFeed()
            }
        }
        .onChange(of: selectedFilter) { _, _ in
            visiblePostCount = 20
        }
        .onChange(of: selectedCategory) { _, _ in
            visiblePostCount = 20
        }
        .onReceive(NotificationCenter.default.publisher(for: .newPostCreated)) { notification in
            guard let userInfo = notification.userInfo else { return }

            if let category = userInfo["category"] as? String,
               category == "testimonies" || category == Post.PostCategory.testimonies.rawValue {
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                currentToast = Toast(type: .success, message: "Testimony shared! 🙏")
                return
            }

            if let post = userInfo["post"] as? Post, post.category == .testimonies {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                dlog("✅ New testimony from \(post.authorName) added to feed")
            }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        VStack(alignment: .leading, spacing: 20) {
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
                .padding(.horizontal)
            } else {
                // Category subtitle removed — tagline lives in the header
            }
            
            // Filters - Center Aligned
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    ForEach(TestimonyFilter.allCases, id: \.self) { filter in
                        Button {
                            selectedFilter = filter
                            filterHaptic.impactOccurred()
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
                        .buttonStyle(.plain)
                    }
                }
                .animation(.easeOut(duration: fastAnimationDuration), value: selectedFilter)
                Spacer()
            }
            .padding(.horizontal)
            
            // Collapsible Categories Section
            VStack(alignment: .leading, spacing: 12) {
                // Category Header Button
                Button {
                    isCategoryBrowseExpanded.toggle()
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
                .buttonStyle(.plain)
                .animation(.easeOut(duration: standardAnimationDuration), value: isCategoryBrowseExpanded)
                
                // Expandable Category Grid
                if isCategoryBrowseExpanded {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        let allPosts = postsManager.testimoniesPosts
                        TestimonyCategoryCard(
                            category: .healing,
                            isSelected: selectedCategory?.title == TestimonyCategory.healing.title,
                            count: allPosts.filter { $0.topicTag?.lowercased() == "healing" }.count
                        ) {
                            selectedCategory = .healing
                            isCategoryBrowseExpanded = false
                        }
                        TestimonyCategoryCard(
                            category: .career,
                            isSelected: selectedCategory?.title == TestimonyCategory.career.title,
                            count: allPosts.filter { $0.topicTag?.lowercased() == "career" }.count
                        ) {
                            selectedCategory = .career
                            isCategoryBrowseExpanded = false
                        }
                        TestimonyCategoryCard(
                            category: .relationship,
                            isSelected: selectedCategory?.title == TestimonyCategory.relationship.title,
                            count: allPosts.filter { ["relationships", "relationship"].contains($0.topicTag?.lowercased() ?? "") }.count
                        ) {
                            selectedCategory = .relationship
                            isCategoryBrowseExpanded = false
                        }
                        TestimonyCategoryCard(
                            category: .financial,
                            isSelected: selectedCategory?.title == TestimonyCategory.financial.title,
                            count: allPosts.filter { $0.topicTag?.lowercased() == "financial" }.count
                        ) {
                            selectedCategory = .financial
                            isCategoryBrowseExpanded = false
                        }
                        TestimonyCategoryCard(
                            category: .spiritual,
                            isSelected: selectedCategory?.title == TestimonyCategory.spiritual.title,
                            count: allPosts.filter { ["spiritual growth", "spiritual"].contains($0.topicTag?.lowercased() ?? "") }.count
                        ) {
                            selectedCategory = .spiritual
                            isCategoryBrowseExpanded = false
                        }
                        TestimonyCategoryCard(
                            category: .family,
                            isSelected: selectedCategory?.title == TestimonyCategory.family.title,
                            count: allPosts.filter { $0.topicTag?.lowercased() == "family" }.count
                        ) {
                            selectedCategory = .family
                            isCategoryBrowseExpanded = false
                        }
                    }
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .top)).animation(.easeOut(duration: standardAnimationDuration)))
                }
            }
            
            // Filtered testimonies feed
            LazyVStack(spacing: 16) {
                let allPosts = filteredPosts
                let displayPosts = Array(allPosts.prefix(visiblePostCount))

                ForEach(Array(displayPosts.enumerated()), id: \.element.id) { index, post in
                    testimonyRow(post: post, index: index, total: displayPosts.count, allCount: allPosts.count)
                }

                // Loading indicator for pagination
                if isLoadingMore && visiblePostCount < allPosts.count {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.vertical, 20)
                        Spacer()
                    }
                }

                // Empty state
                if filteredPosts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: selectedFilter == .following ? "person.2" : "hands.sparkles")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        if selectedFilter == .following {
                            Text("No testimonies from people you follow")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                            Text("Follow others to see their testimonies here.")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        } else if selectedCategory != nil {
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
    }
    
    // MARK: - Helper Functions

    private func testimonyRow(post: Post, index: Int, total: Int, allCount: Int) -> some View {
        PostCard(post: post, isUserPost: post.authorId == Auth.auth().currentUser?.uid)
            .feedItemAppear(id: post.id, delay: min(Double(index) * 0.04, 0.20))
            .onAppear {
                testimonyAlgorithm.recordInteraction(with: post, type: .view)
                if index >= total - 3 && !isLoadingMore && visiblePostCount < allCount {
                    loadMorePosts()
                }
            }
    }

    /// Personalize testimonies feed using algorithm
    private func personalizeTestimoniesFeed() {
        guard !postsManager.testimoniesPosts.isEmpty else {
            personalizedPosts = []
            return
        }

        // Snapshot posts at call time to avoid capturing stale state during async work
        let snapshot = postsManager.testimoniesPosts
        let prefs = testimonyAlgorithm.userPreferences

        Task.detached(priority: .userInitiated) {
            let ranked = await testimonyAlgorithm.rankTestimonies(snapshot, for: prefs)
            await MainActor.run {
                personalizedPosts = ranked
                dlog("✨ Testimonies personalized: \(personalizedPosts.count) posts ranked")
            }
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
        postsManager.deletePost(postId: post.id)
        currentToast = Toast(type: .info, message: "Testimony removed")
    }
    
    private func editPost(_ post: Post) {
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        editingPost = post
        editedContent = post.content
        showEditSheet = true
    }
    
    private func repostPost(_ post: Post) {
        Task {
            let postId = post.id.uuidString
            
            do {
                let isReposted = try await PostInteractionsService.shared.toggleRepost(postId: postId)
                
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    if isReposted {
                        // Add to user's reposts for profile view
                        postsManager.repostToProfile(originalPost: post)
                        dlog("✅ Reposted: \(post.content)")
                        
                        // Show success toast
                        currentToast = Toast(type: .success, message: "Testimony reposted!")
                    } else {
                        dlog("✅ Removed repost: \(post.content)")
                        currentToast = Toast(type: .info, message: "Repost removed")
                    }
                }
            } catch {
                dlog("❌ Failed to repost: \(error.localizedDescription)")
                
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                    
                    // Show error toast
                    currentToast = Toast(type: .error, message: "Failed to repost. Please try again.")
                }
            }
        }
    }
    
    // MARK: - Data Loading Functions
    
    private func loadInitialTestimonies() async {
        isLoadingPosts = true
        errorMessage = nil
        
        do {
            // PostsManager already loads testimonies
            // Just wait a moment to show loading state
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            await MainActor.run {
                isLoadingPosts = false
                isInitialLoad = false
            }
        } catch {
            await MainActor.run {
                isLoadingPosts = false
                isInitialLoad = false
                errorMessage = "Failed to load testimonies. Pull to refresh."
            }
        }
    }
    
    /// Refresh testimonies with pull-to-refresh
    private func refreshTestimonies() async {
        isLoadingPosts = true
        errorMessage = nil
        dlog("🔄 Refreshing Testimonies posts...")
        
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
            dlog("✅ Testimonies posts refreshed!")
        }
        
        // Reset pagination after refresh
        visiblePostCount = 20
    }
    
    // MARK: - Pagination
    
    /// Load more posts when user scrolls near the bottom
    private func loadMorePosts() {
        guard !isLoadingMore else { return }
        
        isLoadingMore = true
        
        // Simulate a brief delay for smooth loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let increment = 10
            let maxCount = filteredPosts.count
            visiblePostCount = min(visiblePostCount + increment, maxCount)
            isLoadingMore = false
        }
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
    let count: Int?
    let action: () -> Void
    @State private var showCategoryDetail = false

    init(category: TestimonyCategory, isSelected: Bool, count: Int? = nil, action: @escaping () -> Void) {
        self.category = category
        self.isSelected = isSelected
        self.count = count
        self.action = action
    }
    
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
                
                Text(count != nil ? "\(count!) \(count == 1 ? "Story" : "Stories")" : category.subtitle)
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
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
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
                    isFollowing.toggle()
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
                .buttonStyle(.plain)
                .symbolEffect(.bounce, value: isFollowing)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFollowing)
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
            Task {
                await toggleAmen()
            }
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
    
    private func toggleAmen() async {
        // Store previous state for rollback
        let previousAmened = hasAmened
        let previousCount = amenCount
        
        // OPTIMISTIC UPDATE: Update UI immediately for instant feedback
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            hasAmened.toggle()
            amenCount = hasAmened ? amenCount + 1 : amenCount - 1
        }
        
        let haptic = UIImpactFeedbackGenerator(style: hasAmened ? .medium : .light)
        haptic.impactOccurred()
        
        // Background sync to Firebase
        let postId = post.id.uuidString
        
        do {
            let interactionsService = PostInteractionsService.shared
            try await interactionsService.toggleAmen(postId: postId)
        } catch {
            dlog("❌ Failed to toggle amen: \(error)")
            
            // On error, revert the optimistic update
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    hasAmened = previousAmened
                    amenCount = previousCount
                }
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
    }
    
    private var commentButton: some View {
        Button {
            showFullCommentSheet = true
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
        .buttonStyle(.plain)
    }
    
    private var repostButton: some View {
        Button {
            Task {
                await toggleRepost()
            }
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
    
    private func toggleRepost() async {
        // Store previous state for rollback
        let previousReposted = hasReposted
        let previousCount = repostCount
        
        // OPTIMISTIC UPDATE: Update UI immediately
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            hasReposted.toggle()
            repostCount += hasReposted ? 1 : -1
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        // Also call the onRepost closure
        onRepost()
        
        // Background sync to Firebase
        let postId = post.id.uuidString
        
        do {
            let interactionsService = PostInteractionsService.shared
            _ = try await interactionsService.toggleRepost(postId: postId)
        } catch {
            dlog("❌ Failed to toggle repost: \(error)")
            
            // On error, revert the optimistic update
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    hasReposted = previousReposted
                    repostCount = previousCount
                }
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
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
            
            // Content (with translation support)
            TranslatableTextBlock(
                text: post.content,
                contentType: .testimony,
                contentId: post.firebaseId ?? post.id.uuidString,
                surface: .feed,
                isPublicContent: true,
                font: .custom("OpenSans-Regular", size: 15),
                foregroundColor: .primary
            )
            
            // Engagement Actions - Prayer UI Style
            engagementActionsView
            
            // Comment Section - Thread connector + inline preview
            if showComments {
                // Threads-style connector line
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 2, height: 24)
                        .padding(.leading, 20)
                    Spacer()
                }

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
        .task {
            // Load interaction states when view appears
            await loadInteractionStates()
        }
    }
    
    // MARK: - Helper Functions
    
    /// Load interaction states from Firebase
    private func loadInteractionStates() async {
        let postId = post.id.uuidString
        let interactionsService = PostInteractionsService.shared
        
        // Check if user has amened
        hasAmened = await interactionsService.hasAmened(postId: postId)
        
        // Check if user has reposted
        hasReposted = await interactionsService.hasReposted(postId: postId)
        
        // Update counts from backend (only if different from initial values)
        let counts = await interactionsService.getInteractionCounts(postId: postId)
        amenCount = counts.amenCount
        commentCount = counts.commentCount
        repostCount = counts.repostCount
    }
    
    private func sharePost() {
        showShareSheet = true
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func copyLink() {
        UIPasteboard.general.string = "https://amenapp.com/testimony/\(post.id.uuidString)"
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        dlog("🔗 Link copied to clipboard")
    }
    
    private func muteAuthor() {
        Task {
            do {
                try await ModerationService.shared.muteUser(userId: post.authorId)
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                dlog("❌ Failed to mute \(post.authorName): \(error.localizedDescription)")
            }
        }
    }
    
    private func blockAuthor() {
        Task {
            do {
                try await BlockService.shared.blockUser(userId: post.authorId)
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.warning)
                }
            } catch {
                dlog("❌ Failed to block \(post.authorName): \(error.localizedDescription)")
            }
        }
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
                            .buttonStyle(.plain)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)).animation(.easeOut(duration: 0.15)))
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
                                showQuickResponses.toggle()
                            } label: {
                                Image(systemName: showQuickResponses ? "sparkles.square.filled.on.square" : "sparkles")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.black.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                            .animation(.easeOut(duration: 0.15), value: showQuickResponses)
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
            dlog("❌ Error loading comments: \(error.localizedDescription)")
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
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        comments.insert(newComment.toTestimonyFeedComment(), at: 0)
                        commentCount += 1
                        commentText = ""
                    }
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                dlog("❌ Failed to post comment: \(error.localizedDescription)")
            }
        }
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
                    .buttonStyle(.plain)
                    
                    Button {
                        // Reply to comment
                    } label: {
                        Text("Reply")
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(.black.opacity(0.5))
                    }
                    .buttonStyle(.plain)
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
    @ObservedObject private var postsManager = PostsManager.shared
    private let filterHaptic = UIImpactFeedbackGenerator(style: .light)
    
    enum CategoryFilter: String, CaseIterable {
        case recent = "Recent"
        case popular = "Popular"
        case encouraging = "Most Encouraging"
    }
    
    // Real filtered posts from Firebase via PostsManager
    private var categoryPosts: [Post] {
        let allPosts = postsManager.testimoniesPosts
        // Match both singular and plural forms (e.g. "Relationships" → "relationship")
        let titleLower = category.title.lowercased()
        let filtered = allPosts.filter { post in
            guard let tag = post.topicTag?.lowercased() else { return false }
            return tag == titleLower
                || tag == titleLower.trimmingCharacters(in: .init(charactersIn: "s"))
                || titleLower.hasPrefix(tag)
                || tag.hasPrefix(titleLower)
        }
        switch selectedFilter {
        case .recent:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .popular:
            return filtered.sorted { ($0.amenCount + $0.commentCount) > ($1.amenCount + $1.commentCount) }
        case .encouraging:
            return filtered.sorted { $0.amenCount > $1.amenCount }
        }
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
                                    selectedFilter = filter
                                    filterHaptic.impactOccurred()
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
                    
                    // Testimonies Feed (real data from Firebase)
                    VStack(spacing: 16) {
                        if categoryPosts.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 40))
                                    .foregroundStyle(category.color.opacity(0.5))
                                Text("No testimonies in \(category.title) yet")
                                    .font(.custom("OpenSans-Bold", size: 16))
                                    .foregroundStyle(.primary)
                                Text("Be the first to share your story!")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(categoryPosts) { post in
                                PostCard(post: post, isUserPost: post.authorId == FirebaseManager.shared.currentUser?.uid)
                            }
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
    @ObservedObject private var commentService = CommentService.shared
    
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
            .buttonStyle(.plain)
        } else {
            Button {
                showQuickResponses.toggle()
            } label: {
                Image(systemName: showQuickResponses ? "sparkles.square.filled.on.square" : "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(.black.opacity(0.5))
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.15), value: showQuickResponses)
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
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)).animation(.easeOut(duration: 0.15)))
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
            dlog("❌ Failed to load comments: \(error)")
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
                dlog("❌ Failed to post comment: \(error)")
            }
        }
    }
}


// Note: Toast, InlineErrorBanner, EmptyPostsView, PostListSkeletonView, ToastModifier, and ReportPostSheet
// are defined in ComponentsSharedUIComponents.swift and PostCard.swift and imported globally


#Preview {
    TestimoniesView()
}
