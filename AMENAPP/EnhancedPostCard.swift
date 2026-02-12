//
//  EnhancedPostCard.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Enhanced PostCard with full social features integration:
//  - Comments and replies
//  - Save posts
//  - Reposts with quote option
//

import SwiftUI
import FirebaseFirestore

struct EnhancedPostCard: View {
    let post: Post
    var isUserPost: Bool = false
    
    @StateObject private var savedPostsService = SavedPostsService.shared
    @StateObject private var repostService = RepostService.shared
    @StateObject private var commentService = CommentService.shared
    @StateObject private var postsManager = PostsManager.shared
    @EnvironmentObject var userService: UserService
    
    @State private var showComments = false
    @State private var showQuoteRepost = false
    @State private var showSaveToCollection = false
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var showUserProfile = false
    @State private var hasLitLightbulb = false
    @State private var hasSaidAmen = false
    @State private var isSaved = false
    @State private var hasReposted = false
    @State private var currentCommentCount: Int = 0  // ✅ Track live comment count
    @State private var currentProfileImageURL: String? = nil  // ✅ Real-time profile image
    @State private var showChurchNoteShareSheet = false  // Share church note
    @State private var loadedChurchNote: ChurchNote? = nil  // Loaded church note
    
    private var category: PostCard.PostCardCategory {
        post.category.cardCategory
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // MARK: - Header
            HStack(spacing: 12) {
                // Avatar (tappable) - ✅ Show profile photo with caching
                Button {
                    showUserProfile = true
                } label: {
                    ZStack {
                        // Background gradient (always show as base)
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [category.color.opacity(0.2), category.color.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        // ✅ Show real-time profile photo with caching
                        Group {
                            if let profileImageURL = currentProfileImageURL ?? post.authorProfileImageURL, !profileImageURL.isEmpty {
                                CachedAsyncImage(url: URL(string: profileImageURL)) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 44, height: 44)
                                        .clipShape(Circle())
                                } placeholder: {
                                    // Show initials while loading
                                    Text(post.authorInitials)
                                        .font(.custom("OpenSans-Bold", size: 16))
                                        .foregroundStyle(category.color)
                                }
                                .onAppear {
                                    print("🖼️ [AVATAR] Displaying profile image: \(profileImageURL.prefix(50))...")
                                }
                                .id("enhanced-\(profileImageURL)")
                            } else {
                                // Show initials if no profile photo
                                Text(post.authorInitials)
                                    .font(.custom("OpenSans-Bold", size: 16))
                                    .foregroundStyle(category.color)
                                    .onAppear {
                                        print("⚪️ [AVATAR] No profile image - showing initials for: \(post.authorName)")
                                        print("   currentProfileImageURL: \(currentProfileImageURL ?? "nil")")
                                        print("   post.authorProfileImageURL: \(post.authorProfileImageURL ?? "nil")")
                                    }
                                    .id("enhanced-initials")
                            }
                        }
                        .onChange(of: currentProfileImageURL) { oldValue, newValue in
                            print("🔄 [ENHANCED_POSTCARD] currentProfileImageURL changed from \(oldValue?.prefix(30) ?? "nil") to \(newValue?.prefix(30) ?? "nil")")
                        }
                    }
                }
                .buttonStyle(.plain)
                
                // Name and info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(post.authorName)
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(.primary)
                        
                        if category != .openTable {
                            HStack(spacing: 4) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(category.displayName)
                                    .font(.custom("OpenSans-Bold", size: 11))
                            }
                            .foregroundStyle(category.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(category.color.opacity(0.15)))
                        }
                    }
                    
                    HStack(spacing: 6) {
                        Text(post.timeAgo)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                        
                        if let tag = post.topicTag {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(tag)
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(category.color)
                        }
                    }
                }
                
                Spacer()
                
                // Menu
                Menu {
                    if isUserPost {
                        Button {
                            showEditSheet = true
                        } label: {
                            Label("Edit Post", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("Delete Post", systemImage: "trash")
                        }
                        
                        Divider()
                    }
                    
                    Menu {
                        Button {
                            Task {
                                try await repostService.repost(postId: post.backendId)
                            }
                        } label: {
                            Label("Repost", systemImage: "arrow.2.squarepath")
                        }
                        
                        Button {
                            showQuoteRepost = true
                        } label: {
                            Label("Quote Repost", systemImage: "quote.bubble")
                        }
                    } label: {
                        Label("Repost Options", systemImage: "arrow.triangle.2.circlepath")
                    }
                    
                    Menu {
                        Button {
                            Task {
                                try await savedPostsService.savePost(postId: post.id.uuidString)
                            }
                        } label: {
                            Label("Save to All", systemImage: "bookmark")
                        }
                        
                        ForEach(savedPostsService.collections.filter { $0 != "All" }, id: \.self) { collection in
                            Button {
                                Task {
                                    try await savedPostsService.savePost(
                                        postId: post.backendId,
                                        collection: collection
                                    )
                                }
                            } label: {
                                Label("Save to \(collection)", systemImage: "folder")
                            }
                        }
                        
                        Divider()
                        
                        Button {
                            showSaveToCollection = true
                        } label: {
                            Label("New Collection...", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Label("Save Options", systemImage: "bookmark")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.6))
                        .frame(width: 32, height: 32)
                }
            }
            
            // MARK: - Content
            Text(post.content)
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.primary)
                .lineSpacing(6)
            
            // ✅ Display post images if available
            if let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                PostImagesView(imageURLs: imageURLs)
                    .padding(.top, 12)
            }
            
            // ✅ NEW: Link button if post has a link
            if let linkURL = post.linkURL, !linkURL.isEmpty {
                PostLinkButton(url: linkURL)
                    .padding(.top, 12)
            }
            
            // Repost indicator
            if post.isRepost, let originalAuthor = post.originalAuthorName {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Reposted from \(originalAuthor)")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(.systemGray6)))
            }
            
            // MARK: - Action Buttons
            HStack(spacing: 8) {
                // Amen/Lightbulb
                if category == .openTable {
                    Button {
                        toggleLightbulb()
                    } label: {
                        ActionButton(
                            icon: hasLitLightbulb ? "lightbulb.fill" : "lightbulb",
                            count: post.lightbulbCount,
                            isActive: hasLitLightbulb,
                            activeColor: .yellow
                        )
                    }
                    .symbolEffect(.bounce, value: hasLitLightbulb)
                } else {
                    Button {
                        toggleAmen()
                    } label: {
                        ActionButton(
                            icon: hasSaidAmen ? "hands.clap.fill" : "hands.clap",
                            count: post.amenCount,
                            isActive: hasSaidAmen,
                            activeColor: .black
                        )
                    }
                    .symbolEffect(.bounce, value: hasSaidAmen)
                }
                
                // Comments - ✅ Use live count from state
                Button {
                    showComments = true
                } label: {
                    ActionButton(
                        icon: "bubble.left.fill",
                        count: currentCommentCount,
                        isActive: false
                    )
                }
                
                // Reposts
                Menu {
                    Button {
                        Task {
                            if hasReposted {
                                try await repostService.unrepost(postId: post.backendId)
                            } else {
                                try await repostService.repost(postId: post.backendId)
                            }
                        }
                    } label: {
                        Label(hasReposted ? "Unrepost" : "Repost", 
                              systemImage: "arrow.2.squarepath")
                    }
                    
                    Button {
                        showQuoteRepost = true
                    } label: {
                        Label("Quote Repost", systemImage: "quote.bubble")
                    }
                    
                    Divider()
                    
                    Button {
                        // Show who reposted
                    } label: {
                        Label("See who reposted", systemImage: "person.2")
                    }
                } label: {
                    ActionButton(
                        icon: "arrow.2.squarepath",
                        count: post.repostCount,
                        isActive: hasReposted,
                        activeColor: .green
                    )
                }
                
                Spacer()
                
                // Share Church Note (only if post has a church note)
                if post.churchNoteId != nil {
                    Button {
                        showChurchNoteShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
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
                
                // Save
                Button {
                    Task {
                        try await savedPostsService.toggleSave(postId: post.id.uuidString)
                    }
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSaved ? .blue : .black.opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSaved ? Color.blue.opacity(0.1) : Color.black.opacity(0.05))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSaved ? Color.blue.opacity(0.3) : Color.black.opacity(0.1), lineWidth: 1)
                        )
                }
                .symbolEffect(.bounce, value: isSaved)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
        .task {
            print("🎬 [CARD] .task fired for post: \(post.backendId.prefix(8))")
            await loadInteractionStates()
            await fetchLatestProfileImage()
        }
        .onAppear {
            print("👀 [CARD] .onAppear fired for post: \(post.backendId.prefix(8))")
            print("   Current states - Lightbulb: \(hasLitLightbulb), Amen: \(hasSaidAmen), Saved: \(isSaved), Reposted: \(hasReposted)")
            
            // ✅ Refresh states every time view appears (handles tab switches + app resume)
            Task {
                await refreshInteractionStates()
            }
        }
        .sheet(isPresented: $showComments) {
            CommentsView(post: post)
                .environmentObject(userService)
                .onDisappear {
                    // ✅ Refresh comment count when comments sheet closes
                    print("📊 [POST CARD] Comments sheet dismissed, refreshing count...")
                    print("   Post ID: \(post.backendId)")
                    print("   Current count in UI: \(currentCommentCount)")
                    Task {
                        let count = await PostInteractionsService.shared.getCommentCount(postId: post.backendId)
                        print("   ✅ Fetched count from RTDB: \(count)")
                        await MainActor.run {
                            let oldCount = currentCommentCount
                            currentCommentCount = count
                            print("   📈 Updated UI: \(oldCount) → \(currentCommentCount)")
                        }
                    }
                }
        }
        .sheet(isPresented: $showQuoteRepost) {
            QuoteRepostView(post: post)
        }
        .sheet(isPresented: $showSaveToCollection) {
            CreateCollectionView(postId: post.id.uuidString)
        }
        .sheet(isPresented: $showEditSheet) {
            EditPostSheet(post: post)
        }
        .sheet(isPresented: $showChurchNoteShareSheet) {
            if let churchNote = loadedChurchNote {
                ChurchNoteShareOptionsSheet(note: churchNote)
            } else {
                ProgressView("Loading church note...")
                    .task {
                        await loadChurchNote()
                    }
            }
        }
        .alert("Delete Post", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deletePost()
            }
        } message: {
            Text("Are you sure you want to delete this post? This action cannot be undone.")
        }
        .onChange(of: savedPostsService.savedPostIds) { _, newSet in
            // Batch update to prevent multiple updates per frame
            Task { @MainActor in
                print("🔔 [CARD] savedPostIds changed, updating saved state")
                updateSavedState()
            }
        }
        .onChange(of: repostService.repostedPostIds) { _, newSet in
            // Batch update to prevent multiple updates per frame
            Task { @MainActor in
                print("🔔 [CARD] repostedPostIds changed, updating repost state")
                updateRepostState()
            }
        }
        .onChange(of: PostInteractionsService.shared.userLightbulbedPosts) { oldSet, newSet in
            // ✅ NEW: Observe lightbulb changes from PostInteractionsService
            let wasLit = oldSet.contains(post.backendId)
            let isLit = newSet.contains(post.backendId)
            if wasLit != isLit {
                // Batch update to prevent multiple updates per frame
                Task { @MainActor in
                    print("🔔 [CARD] Lightbulb state changed via service: \(wasLit) → \(isLit)")
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        hasLitLightbulb = isLit
                    }
                }
            }
        }
        .onChange(of: PostInteractionsService.shared.userAmenedPosts) { oldSet, newSet in
            // ✅ NEW: Observe amen changes from PostInteractionsService
            let wasAmened = oldSet.contains(post.backendId)
            let isAmened = newSet.contains(post.backendId)
            if wasAmened != isAmened {
                // Batch update to prevent multiple updates per frame
                Task { @MainActor in
                    print("🔔 [CARD] Amen state changed via service: \(wasAmened) → \(isAmened)")
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        hasSaidAmen = isAmened
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("commentsUpdated"))) { notification in
            // ✅ Listen for comment updates and refresh count
            if let postId = notification.userInfo?["postId"] as? String,
               postId == post.backendId {
                print("🔔 [POST CARD] Received commentsUpdated notification for post: \(postId)")
                Task {
                    let count = await PostInteractionsService.shared.getCommentCount(postId: post.backendId)
                    print("   📊 Fetched count from notification: \(count)")
                    await MainActor.run {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            let oldCount = currentCommentCount
                            currentCommentCount = count
                            print("   ✨ Animated update: \(oldCount) → \(currentCommentCount)")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadInteractionStates() async {
        // ✅ Initialize comment count from post
        currentCommentCount = post.commentCount
        
        // ✅ OPTIMIZED: Load all states in parallel using TaskGroup
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let saved = await self.savedPostsService.isPostSaved(postId: self.post.id.uuidString)
                await MainActor.run { 
                    self.isSaved = saved
                    print("   📊 Initial saved state: \(saved)")
                }
            }
            
            group.addTask {
                let reposted = await self.repostService.hasReposted(postId: self.post.backendId)
                await MainActor.run { 
                    self.hasReposted = reposted
                    print("   📊 Initial reposted state: \(reposted)")
                }
            }
            
            group.addTask {
                let lit = await PostInteractionsService.shared.hasLitLightbulb(postId: self.post.backendId)
                await MainActor.run { 
                    self.hasLitLightbulb = lit
                    print("   📊 Initial lightbulb state: \(lit)")
                }
            }
            
            group.addTask {
                let amened = await PostInteractionsService.shared.hasAmened(postId: self.post.backendId)
                await MainActor.run { 
                    self.hasSaidAmen = amened
                    print("   📊 Initial amen state: \(amened)")
                }
            }
            
            // ✅ NEW: Load real-time comment count from RTDB
            group.addTask {
                let count = await PostInteractionsService.shared.getCommentCount(postId: self.post.backendId)
                await MainActor.run { 
                    self.currentCommentCount = count
                    print("   📊 Initial comment count: \(count)")
                }
            }
        }
    }
    
    /// ✅ Fetch latest profile image from Firestore (real-time updates)
    private func fetchLatestProfileImage() async {
        // Only fetch if we have a valid author ID
        guard !post.authorId.isEmpty else {
            print("⚠️ [PROFILE_IMG] No author ID for post")
            return
        }
        
        print("🔍 [PROFILE_IMG] Fetching profile image for user: \(post.authorId)")
        print("   Post already has URL: \(post.authorProfileImageURL ?? "none")")
        
        do {
            let db = Firestore.firestore()
            let userDoc = try await db.collection("users").document(post.authorId).getDocument()

            // ✅ Handle both String values and null values from Firestore
            if let userData = userDoc.data() {
                let rawValue = userData["profileImageURL"]

                // Handle case where value is explicitly null (NSNull)
                if rawValue is NSNull {
                    print("⚠️ [PROFILE_IMG] profileImageURL is explicitly null in Firestore")
                    return
                }

                // Try to get as String
                if let profileImageURL = rawValue as? String, !profileImageURL.isEmpty {
                    print("✅ [PROFILE_IMG] Found profile image URL: \(profileImageURL)")
                    await MainActor.run {
                        currentProfileImageURL = profileImageURL
                    }
                } else {
                    print("⚠️ [PROFILE_IMG] No valid profile image URL")
                }
            }
        } catch {
            print("❌ [PROFILE_IMG] Error fetching profile image for user \(post.authorId): \(error.localizedDescription)")
        }
    }
    
    /// ✅ NEW: Refresh interaction states when view reappears (handles tab switches + app resume)
    private func refreshInteractionStates() async {
        print("🔄 [CARD] Refreshing interaction states from Firebase...")
        
        // ✅ CRITICAL: Re-query Firebase to get latest state (not cached)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let saved = await self.savedPostsService.isPostSaved(postId: self.post.id.uuidString)
                await MainActor.run {
                    if self.isSaved != saved {
                        print("   🔄 Saved state changed: \(self.isSaved) → \(saved)")
                        self.isSaved = saved
                    }
                }
            }
            
            group.addTask {
                let reposted = await self.repostService.hasReposted(postId: self.post.backendId)
                await MainActor.run {
                    if self.hasReposted != reposted {
                        print("   🔄 Reposted state changed: \(self.hasReposted) → \(reposted)")
                        self.hasReposted = reposted
                    }
                }
            }
            
            group.addTask {
                // ✅ CRITICAL: Query RTDB directly, not from cache
                let lit = await PostInteractionsService.shared.hasLitLightbulb(postId: self.post.backendId)
                await MainActor.run {
                    if self.hasLitLightbulb != lit {
                        print("   🔄 Lightbulb state changed: \(self.hasLitLightbulb) → \(lit)")
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            self.hasLitLightbulb = lit
                        }
                    }
                }
            }
            
            group.addTask {
                // ✅ CRITICAL: Query RTDB directly, not from cache
                let amened = await PostInteractionsService.shared.hasAmened(postId: self.post.backendId)
                await MainActor.run {
                    if self.hasSaidAmen != amened {
                        print("   🔄 Amen state changed: \(self.hasSaidAmen) → \(amened)")
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            self.hasSaidAmen = amened
                        }
                    }
                }
            }
            
            group.addTask {
                let count = await PostInteractionsService.shared.getCommentCount(postId: self.post.backendId)
                await MainActor.run {
                    if self.currentCommentCount != count {
                        print("   🔄 Comment count changed: \(self.currentCommentCount) → \(count)")
                        self.currentCommentCount = count
                    }
                }
            }
        }
        
        print("✅ [CARD] Refresh complete - Lightbulb: \(hasLitLightbulb), Amen: \(hasSaidAmen), Saved: \(isSaved), Reposted: \(hasReposted)")
    }
    
    private func updateSavedState() {
        let newState = savedPostsService.savedPostIds.contains(post.id.uuidString)
        if isSaved != newState {
            print("   📌 Saved state updated: \(isSaved) → \(newState)")
            isSaved = newState
        }
    }
    
    private func updateRepostState() {
        let newState = repostService.repostedPostIds.contains(post.backendId)
        if hasReposted != newState {
            print("   🔄 Repost state updated: \(hasReposted) → \(newState)")
            hasReposted = newState
        }
    }
    
    private func toggleLightbulb() {
        // ✅ OPTIMIZED: Update UI instantly (optimistic update)
        hasLitLightbulb.toggle()
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        // Save to Firebase in background
        let currentState = hasLitLightbulb
        Task {
            do {
                try await PostInteractionsService.shared.toggleLightbulb(postId: post.backendId)
            } catch {
                // Revert on error
                await MainActor.run {
                    hasLitLightbulb = !currentState
                }
            }
        }
    }
    
    private func toggleAmen() {
        // ✅ OPTIMIZED: Update UI instantly (optimistic update)
        hasSaidAmen.toggle()
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        // Save to Firebase in background
        let currentState = hasSaidAmen
        Task {
            do {
                try await PostInteractionsService.shared.toggleAmen(postId: post.backendId)
            } catch {
                // Revert on error
                await MainActor.run {
                    hasSaidAmen = !currentState
                }
            }
        }
    }
    
    private func deletePost() {
        postsManager.deletePost(postId: post.id)
    }
    
    private func loadChurchNote() async {
        guard let churchNoteId = post.churchNoteId else { return }
        
        do {
            let db = Firestore.firestore()
            let document = try await db.collection("churchNotes").document(churchNoteId).getDocument()
            
            if let note = try? document.data(as: ChurchNote.self) {
                await MainActor.run {
                    loadedChurchNote = note
                }
            }
        } catch {
            print("❌ Error loading church note: \(error.localizedDescription)")
        }
    }
}

// MARK: - Action Button Component

private struct ActionButton: View {
    let icon: String
    let count: Int
    var isActive: Bool = false
    var activeColor: Color = .blue
    
    var body: some View {
        // Just show icon - no count numbers
        Image(systemName: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isActive ? activeColor : Color.black.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isActive ? activeColor.opacity(0.15) : Color.black.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? activeColor.opacity(0.3) : Color.black.opacity(0.1), lineWidth: 1)
            )
    }
}

// MARK: - Quote Repost View

struct QuoteRepostView: View {
    let post: Post
    
    @StateObject private var repostService = RepostService.shared
    @State private var comment = ""
    @State private var isPosting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Input area
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add your thoughts")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                    
                    TextEditor(text: $comment)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .frame(height: 120)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                }
                .padding(.horizontal)
                
                // Original post preview
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reposting")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    
                    EnhancedPostCard(post: post)
                        .opacity(0.8)
                        .padding(.horizontal)
                }
                
                Spacer()
            }
            .navigationTitle("Quote Repost")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submitQuoteRepost()
                    } label: {
                        if isPosting {
                            ProgressView()
                        } else {
                            Text("Repost")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                        }
                    }
                    .disabled(comment.isEmpty || isPosting)
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func submitQuoteRepost() {
        isPosting = true
        
        Task {
            do {
                try await repostService.repost(
                    postId: post.id.uuidString,
                    withComment: comment
                )
                
                dismiss()
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            
            isPosting = false
        }
    }
}

// MARK: - Create Collection View

struct CreateCollectionView: View {
    let postId: String
    
    @StateObject private var savedPostsService = SavedPostsService.shared
    @State private var collectionName = ""
    @State private var isCreating = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Collection Name", text: $collectionName)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
                    .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        createCollection()
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(collectionName.isEmpty || isCreating)
                }
            }
        }
    }
    
    private func createCollection() {
        isCreating = true
        
        Task {
            do {
                try await savedPostsService.createCollection(name: collectionName)
                try await savedPostsService.savePost(postId: postId, collection: collectionName)
                dismiss()
            } catch {
                print("Error creating collection: \(error)")
            }
            
            isCreating = false
        }
    }
}

// MARK: - Post Images View

struct PostImagesView: View {
    let imageURLs: [String]
    @State private var selectedImageIndex: Int? = nil
    
    var body: some View {
        let imageCount = imageURLs.count
        
        if imageCount == 1 {
            // Single image - full width
            singleImageView(url: imageURLs[0])
                .onTapGesture {
                    selectedImageIndex = 0
                }
        } else if imageCount == 2 {
            // Two images - side by side
            HStack(spacing: 4) {
                ForEach(0..<2, id: \.self) { index in
                    imageView(url: imageURLs[index])
                        .onTapGesture {
                            selectedImageIndex = index
                        }
                }
            }
            .frame(height: 240)
        } else if imageCount == 3 {
            // Three images - first one full width, two below side by side
            VStack(spacing: 4) {
                imageView(url: imageURLs[0])
                    .frame(height: 240)
                    .onTapGesture {
                        selectedImageIndex = 0
                    }
                
                HStack(spacing: 4) {
                    imageView(url: imageURLs[1])
                        .onTapGesture {
                            selectedImageIndex = 1
                        }
                    imageView(url: imageURLs[2])
                        .onTapGesture {
                            selectedImageIndex = 2
                        }
                }
                .frame(height: 120)
            }
        } else {
            // Four or more images - 2x2 grid
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    imageView(url: imageURLs[0])
                        .onTapGesture {
                            selectedImageIndex = 0
                        }
                    imageView(url: imageURLs[1])
                        .onTapGesture {
                            selectedImageIndex = 1
                        }
                }
                .frame(height: 120)
                
                HStack(spacing: 4) {
                    imageView(url: imageURLs[2])
                        .onTapGesture {
                            selectedImageIndex = 2
                        }
                    
                    if imageCount > 3 {
                        ZStack {
                            imageView(url: imageURLs[3])
                            
                            // Show "+X more" overlay if there are more than 4 images
                            if imageCount > 4 {
                                Color.black.opacity(0.6)
                                Text("+\(imageCount - 4)")
                                    .font(.custom("OpenSans-Bold", size: 24))
                                    .foregroundStyle(.white)
                            }
                        }
                        .onTapGesture {
                            selectedImageIndex = 3
                        }
                    }
                }
                .frame(height: 120)
            }
        }
    }
    
    private func singleImageView(url: String) -> some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            case .failure:
                placeholderView
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            @unknown default:
                placeholderView
            }
        }
    }
    
    private func imageView(url: String) -> some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            case .failure:
                placeholderView
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            @unknown default:
                placeholderView
            }
        }
    }
    
    private var placeholderView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray6))
            
            Image(systemName: "photo")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EnhancedPostCard(
        post: Post(
            authorName: "John Disciple",
            authorInitials: "JD",
            content: "This is a test post with all the new social features!",
            category: .openTable,
            topicTag: "Tech & Faith"
        )
    )
    .environmentObject(UserService())
}
