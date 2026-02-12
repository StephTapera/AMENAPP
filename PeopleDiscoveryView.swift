//
//  PeopleDiscoveryView.swift
//  AMENAPP
//
//  Created by Steph on 1/28/26.
//
//  Production-ready people discovery with clean black & white design
//  Focused on finding and connecting with people
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - People Discovery View (Liquid Glass Design)

struct PeopleDiscoveryViewNew: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PeopleDiscoveryViewModelNew()
    @State private var searchText = ""
    @State private var selectedFilter: DiscoveryFilter = .suggested
    @State private var showProfileSheet: UserModel?
    
    enum DiscoveryFilter: String, CaseIterable {
        case suggested = "Suggested"
        case recent = "Recent"
        case posts = "Posts"
        
        var icon: String {
            switch self {
            case .suggested: return "sparkles"
            case .recent: return "clock.fill"
            case .posts: return "square.grid.2x2.fill"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Elegant gradient background
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.05, green: 0.05, blue: 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with back button (always shown)
                    headerSection
                    
                    // Search bar (only for people discovery, not posts)
                    if selectedFilter != .posts {
                        liquidGlassSearchSection
                    }
                    
                    // Filter tabs (always shown)
                    liquidGlassFilterSection
                        .background(
                            Color.blue.opacity(0.3)
                                .onTapGesture {
                                    print("🔵 BLUE DEBUG LAYER TAPPED - touches ARE reaching this area")
                                }
                        )
                    
                    // Conditional content based on filter
                    if selectedFilter == .posts {
                        // Show PostsSearchView for Posts filter
                        PostsSearchView()
                    } else {
                        // Show People Discovery content for Suggested/Recent filters
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 12) {
                                if viewModel.isLoading && viewModel.users.isEmpty {
                                    loadingView
                                } else if viewModel.users.isEmpty {
                                    emptyStateView
                                } else {
                                    ForEach(viewModel.users.filter { $0.id != nil }) { user in
                                        PeopleDiscoveryPersonCard(
                                            user: user,
                                            onTap: {
                                                showProfileSheet = user
                                            },
                                            viewModel: viewModel
                                        )
                                    }
                                    
                                    // Load more trigger
                                    if viewModel.hasMore {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.5)))
                                            .frame(height: 50)
                                            .onAppear {
                                                Task { await viewModel.loadMore() }
                                            }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                        .refreshable {
                            await viewModel.refresh()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $showProfileSheet) { user in
                if let userId = user.id, !userId.isEmpty {
                    NavigationView {
                        SafeUserProfileWrapper(userId: userId)
                    }
                } else {
                    Text("Unable to load profile")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .task {
                await viewModel.loadUsers(filter: selectedFilter)
            }
        }
    }
    
    // MARK: - Header with Back Button
    
    private var headerSection: some View {
        HStack(spacing: 16) {
            // Back button with liquid glass
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                dismiss()
            } label: {
                ZStack {
                    // Liquid glass background
                    Circle()
                        .fill(.ultraThinMaterial.opacity(0.3))
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.3),
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Discover People")
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundColor(.white)
                
                Text("\(viewModel.users.count) believers")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
    }
    
    // MARK: - Liquid Glass Search
    
    private var liquidGlassSearchSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            
            TextField("", text: $searchText, prompt: Text("Search by name or @username").foregroundColor(.white.opacity(0.4)))
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: searchText) { _, newValue in
                    Task {
                        await viewModel.searchUsers(query: newValue)
                    }
                }
            
            if !searchText.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            ZStack {
                // Liquid glass effect
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.3))
                
                // Subtle gradient overlay
                RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                
                // Border
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
    
    // MARK: - Liquid Glass Filters
    
    private var liquidGlassFilterSection: some View {
        HStack(spacing: 12) {
            ForEach(DiscoveryFilter.allCases, id: \.self) { filter in
                // Direct button implementation for better touch reliability
                ZStack {
                    // Background
                    if selectedFilter == filter {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .white.opacity(0.3), radius: 12, y: 6)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.2))
                        
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.2),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    
                    // Content
                    HStack(spacing: 8) {
                        Image(systemName: filter.icon)
                            .font(.system(size: 14, weight: .semibold))
                        
                        Text(filter.rawValue)
                            .font(.custom("OpenSans-SemiBold", size: 15))
                    }
                    .foregroundColor(selectedFilter == filter ? .black : .white.opacity(0.7))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .contentShape(Rectangle()) // Expand tap area
                .onTapGesture {
                    print("🎯 DIRECT TAP: \(filter.rawValue)")
                    
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedFilter = filter
                    }
                    
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    
                    // Only load users if not Posts filter
                    if filter != .posts {
                        Task {
                            await viewModel.loadUsers(filter: filter)
                        }
                    } else {
                        print("✅ Posts filter selected - showing PostsSearchView")
                    }
                }
            }
        }
        .frame(height: 60)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .background(Color.green.opacity(0.2)) // Changed to green to verify this version is loaded
        .onTapGesture {
            print("🚨 HStack container tapped - touch is reaching this view!")
        }
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
            
            Text("Finding people...")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.white.opacity(0.3))
                .symbolEffect(.bounce, value: viewModel.users.isEmpty)
            
            Text("No people found")
                .font(.custom("OpenSans-SemiBold", size: 18))
                .foregroundColor(.white)
            
            Text("Try a different search or filter")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Liquid Glass Filter Chip

struct LiquidGlassFilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            print("🎯 LiquidGlassFilterChip tapped: \(title)")
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 15))
            }
            .foregroundColor(isSelected ? .black : .white.opacity(0.7))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    if isSelected {
                        // Selected: White liquid glass
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .white.opacity(0.3), radius: 12, y: 6)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        // Unselected: Transparent liquid glass
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.2))
                        
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.2),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.75, blendDuration: 0), value: isSelected)
            )
            .contentShape(Rectangle()) // Better tap target
        }
        .buttonStyle(PlainButtonStyle())
        .allowsHitTesting(true)
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - People Discovery Person Card

struct PeopleDiscoveryPersonCard: View {
    let user: UserModel
    let onTap: () -> Void
    @State private var isFollowing = false
    @State private var isPressed = false
    @StateObject private var followService = FollowService.shared
    @ObservedObject var viewModel: PeopleDiscoveryViewModelNew
    @State private var hasAppeared = false // Track appearance for staggered animation
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Avatar with glow
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 35
                            )
                        )
                        .frame(width: 70, height: 70)
                        .blur(radius: 8)
                    
                    // Avatar circle
                    Circle()
                        .fill(.ultraThinMaterial.opacity(0.3))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.4),
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                    
                    if let profileImageURL = user.profileImageURL, !profileImageURL.isEmpty {
                        AsyncImage(url: URL(string: profileImageURL)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(Circle())
                                    .transition(.scale.combined(with: .opacity))
                            default:
                                Text(user.initials)
                                    .font(.custom("OpenSans-Bold", size: 20))
                                    .foregroundColor(.white)
                            }
                        }
                    } else {
                        Text(user.initials)
                            .font(.custom("OpenSans-Bold", size: 20))
                            .foregroundColor(.white)
                    }
                }
                
                // Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(user.displayName)
                        .font(.custom("OpenSans-Bold", size: 17))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("@\(user.username)")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                    
                    if user.followersCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 10))
                            Text("\(user.followersCount) followers")
                                .font(.custom("OpenSans-SemiBold", size: 12))
                        }
                        .foregroundColor(.white.opacity(0.5))
                    }
                    
                    // ✨ Mutual Connections Badge
                    if let userId = user.id {
                        MutualConnectionsBadge(userId: userId)
                    }
                }
                
                Spacer()
                
                // Liquid glass follow button
                LiquidGlassFollowButton(
                    isFollowing: isFollowing,
                    userId: user.id ?? ""
                ) {
                    toggleFollow()
                }
            }
            .padding(16)
            .background(
                ZStack {
                    // Liquid glass background
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.25))
                    
                    // Gradient overlay - only animates on press
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isPressed ? 0.15 : 0.08),
                                    Color.white.opacity(isPressed ? 0.08 : 0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .animation(.easeOut(duration: 0.15), value: isPressed)
                    
                    // Border
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(0.3), radius: 15, y: 8)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 10)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .animation(.easeOut(duration: 0.3), value: hasAppeared)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
        .onAppear {
            // Staggered fade-in animation
            withAnimation {
                hasAppeared = true
            }
            
            // Use cached follow status from viewModel - only check once
            if let userId = user.id {
                isFollowing = viewModel.followingUserIds.contains(userId)
            }
        }
        .onChange(of: viewModel.followingUserIds) { oldValue, newValue in
            // Smart update: only if THIS user's status changed
            if let userId = user.id {
                let wasFollowing = oldValue.contains(userId)
                let nowFollowing = newValue.contains(userId)
                
                if wasFollowing != nowFollowing {
                    isFollowing = nowFollowing
                }
            }
        }
    }
    
    private func toggleFollow() {
        guard let userId = user.id else { return }
        
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isFollowing.toggle()
            
            // Update the cache immediately for instant UI feedback
            if isFollowing {
                viewModel.followingUserIds.insert(userId)
            } else {
                viewModel.followingUserIds.remove(userId)
            }
        }
        
        Task {
            do {
                if isFollowing {
                    try await followService.followUser(userId: userId)
                } else {
                    try await followService.unfollowUser(userId: userId)
                }
            } catch {
                print("❌ Follow action failed: \(error)")
                // Revert on error
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isFollowing.toggle()
                        
                        // Revert cache
                        if isFollowing {
                            viewModel.followingUserIds.insert(userId)
                        } else {
                            viewModel.followingUserIds.remove(userId)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Liquid Glass Follow Button

struct LiquidGlassFollowButton: View {
    let isFollowing: Bool
    let userId: String
    let onTap: () -> Void
    @State private var showCheckmark = false
    
    var body: some View {
        Button(action: {
            onTap()
            // Show brief checkmark animation when following
            if !isFollowing {
                showCheckmark = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showCheckmark = false
                }
            }
        }) {
            HStack(spacing: 6) {
                if !isFollowing && !showCheckmark {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                } else if showCheckmark {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                }
                
                Text(isFollowing ? "Following" : "Follow")
                    .font(.custom("OpenSans-Bold", size: 14))
            }
            .foregroundColor(isFollowing ? .white.opacity(0.7) : .black)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    if isFollowing {
                        // Following state: Liquid glass
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.3))
                        
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.4),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    } else {
                        // Follow state: White solid
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .white.opacity(0.4), radius: 8, y: 4)
                    }
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isFollowing)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - View Model (Production-Ready with Smart Algorithm)

@MainActor
class PeopleDiscoveryViewModelNew: ObservableObject {
    @Published var users: [UserModel] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMore = true
    @Published var error: String?
    @Published var followingUserIds: Set<String> = [] // Cache follow status
    
    private let db = Firestore.firestore()
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 20
    private var searchTask: Task<Void, Never>?
    
    func loadUsers(filter: PeopleDiscoveryViewNew.DiscoveryFilter) async {
        isLoading = true
        lastDocument = nil
        
        do {
            users = try await fetchUsers(filter: filter, limit: pageSize)
            hasMore = users.count >= pageSize
            await loadFollowingStatus() // Batch load all at once
            print("✅ Loaded \(users.count) users for filter: \(filter.rawValue)")
        } catch {
            self.error = error.localizedDescription
            print("❌ Failed to load users: \(error)")
        }
        
        isLoading = false
    }
    
    // Batch load following status - ONE query instead of N queries
    private func loadFollowingStatus() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { 
            print("⚠️ No current user ID, skipping follow status load")
            return 
        }
        
        do {
            let snapshot = try await db
                .collection("users")
                .document(currentUserId)
                .collection("following")
                .getDocuments()
            
            followingUserIds = Set(snapshot.documents.map { $0.documentID })
            print("✅ Loaded following status for \(followingUserIds.count) users")
        } catch let error as NSError {
            // Handle permission errors gracefully
            if error.domain == "FIRFirestoreErrorDomain" && error.code == 7 {
                print("⚠️ Permission denied for following status. Check Firestore rules.")
                print("   Make sure users can read: /users/{userId}/following")
                followingUserIds = [] // Start with empty set
            } else {
                print("❌ Failed to load following status: \(error.localizedDescription)")
            }
        }
    }
    
    func loadMore() async {
        guard !isLoadingMore && hasMore else { return }
        
        isLoadingMore = true
        
        do {
            let newUsers = try await fetchUsers(
                filter: .suggested,
                limit: pageSize,
                afterDocument: lastDocument
            )
            users.append(contentsOf: newUsers)
            hasMore = newUsers.count >= pageSize
            await loadFollowingStatus() // Update follow status for new users
            print("✅ Loaded \(newUsers.count) more users")
        } catch {
            print("❌ Failed to load more users: \(error)")
        }
        
        isLoadingMore = false
    }
    
    func refresh() async {
        await loadUsers(filter: .suggested)
    }
    
    func searchUsers(query: String) async {
        // Cancel previous search task
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            await loadUsers(filter: .suggested)
            return
        }
        
        // Debounce search with Task
        searchTask = Task {
            // Wait 300ms for debouncing
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            guard !Task.isCancelled else { return }
            
            await performSearch(query: query)
        }
    }
    
    private func performSearch(query: String) async {
        isLoading = true
        
        do {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            
            print("🔍 Searching with Algolia for: '\(trimmedQuery)'")
            
            // Use Algolia for fast, typo-tolerant search
            let algoliaUsers = try await AlgoliaSearchService.shared.searchUsers(query: trimmedQuery)
            
            // Convert Algolia users to UserModel
            let results = try await convertAlgoliaUsersToUserModels(algoliaUsers)
            
            // Update users on main thread
            users = results
            await loadFollowingStatus() // Load follow status for search results
            print("✅ Algolia search found \(results.count) users for '\(query)'")
            
        } catch {
            print("❌ Algolia search failed: \(error)")
            // Fallback to Firestore search if Algolia fails
            print("⚠️ Falling back to Firestore search...")
            await performFirestoreSearch(query: query)
        }
        
        isLoading = false
    }
    
    // MARK: - Algolia to UserModel Conversion
    
    private func convertAlgoliaUsersToUserModels(_ algoliaUsers: [AlgoliaUser]) async throws -> [UserModel] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return []
        }
        
        var userModels: [UserModel] = []
        
        // Batch fetch full user data from Firestore
        for algoliaUser in algoliaUsers {
            // Skip current user
            guard algoliaUser.objectID != currentUserId else { continue }
            
            do {
                let doc = try await db.collection("users").document(algoliaUser.objectID).getDocument()
                if let user = try? doc.data(as: UserModel.self), user.id != nil {
                    userModels.append(user)
                }
            } catch {
                print("⚠️ Failed to fetch user \(algoliaUser.objectID): \(error)")
            }
        }
        
        return userModels
    }
    
    // MARK: - Firestore Fallback Search
    
    private func performFirestoreSearch(query: String) async {
        do {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercaseQuery = trimmedQuery.lowercased()
            
            print("🔍 Firestore fallback search for: '\(trimmedQuery)'")
            
            // Strategy 1: Search by username (most common)
            var results = try await searchByUsername(lowercaseQuery)
            
            // Strategy 2: If few results, also search by display name
            if results.count < 5 {
                let nameResults = try await searchByDisplayName(trimmedQuery)
                
                // Merge results, avoiding duplicates
                for user in nameResults {
                    if !results.contains(where: { $0.id == user.id }) {
                        results.append(user)
                    }
                }
            }
            
            // Strategy 3: If still few results, try searchable fields
            if results.count < 3 {
                let searchableResults = try await searchBySearchableFields(lowercaseQuery)
                
                for user in searchableResults {
                    if !results.contains(where: { $0.id == user.id }) {
                        results.append(user)
                    }
                }
            }
            
            users = results
            print("✅ Firestore fallback found \(results.count) users for '\(query)'")
            
        } catch {
            print("❌ Firestore search failed: \(error)")
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Search Strategies
    
    private func searchByUsername(_ query: String) async throws -> [UserModel] {
        let snapshot = try await db.collection("users")
            .whereField("username", isGreaterThanOrEqualTo: query)
            .whereField("username", isLessThanOrEqualTo: query + "\u{f8ff}")
            .limit(to: pageSize)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> UserModel? in
            guard let user = try? doc.data(as: UserModel.self),
                  user.id != nil else {
                return nil
            }
            return user
        }
    }
    
    private func searchByDisplayName(_ query: String) async throws -> [UserModel] {
        let snapshot = try await db.collection("users")
            .whereField("displayName", isGreaterThanOrEqualTo: query)
            .whereField("displayName", isLessThanOrEqualTo: query + "\u{f8ff}")
            .limit(to: pageSize)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> UserModel? in
            guard let user = try? doc.data(as: UserModel.self),
                  user.id != nil else {
                return nil
            }
            return user
        }
    }
    
    private func searchBySearchableFields(_ query: String) async throws -> [UserModel] {
        // Try searching with searchable username/display name fields
        let snapshot = try await db.collection("users")
            .whereField("searchableUsername", isGreaterThanOrEqualTo: query)
            .whereField("searchableUsername", isLessThanOrEqualTo: query + "\u{f8ff}")
            .limit(to: pageSize)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> UserModel? in
            guard let user = try? doc.data(as: UserModel.self),
                  user.id != nil else {
                return nil
            }
            return user
        }
    }
    
    // MARK: - Fetch Users by Filter
    
    private func fetchUsers(
        filter: PeopleDiscoveryViewNew.DiscoveryFilter,
        limit: Int,
        afterDocument: DocumentSnapshot? = nil
    ) async throws -> [UserModel] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "PeopleDiscovery",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        var query = db.collection("users").limit(to: limit)
        
        // Apply filter
        switch filter {
        case .suggested:
            // Smart suggestions: Recent users with followers
            query = query
                .whereField("followersCount", isGreaterThanOrEqualTo: 0)
                .order(by: "followersCount", descending: true)
                .order(by: "createdAt", descending: true)
            
        case .recent:
            // Recently joined users
            query = query.order(by: "createdAt", descending: true)
        }
        
        // Pagination
        if let afterDocument = afterDocument {
            query = query.start(afterDocument: afterDocument)
        }
        
        let snapshot = try await query.getDocuments()
        lastDocument = snapshot.documents.last
        
        // Filter out current user and map to UserModel
        let fetchedUsers = snapshot.documents.compactMap { doc -> UserModel? in
            guard let user = try? doc.data(as: UserModel.self),
                  let userId = user.id,
                  userId != currentUserId else {
                return nil
            }
            return user
        }
        
        return fetchedUsers
    }
}

// MARK: - Safe Profile Wrapper

struct SafeUserProfileWrapper: View {
    let userId: String
    @State private var loadFailed = false
    @State private var isLoading = true
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Group {
            if loadFailed {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    
                    Text("Unable to Load Profile")
                        .font(.custom("OpenSans-Bold", size: 20))
                    
                    Text("This profile could not be loaded. Please try again later.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(.black)
                            )
                    }
                }
                .padding()
            } else {
                UserProfileView(userId: userId, showsDismissButton: true)
                    .task {
                        // Add timeout to detect crashes
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                        isLoading = false
                    }
                    .onDisappear {
                        // Clean up if needed
                        isLoading = false
                    }
            }
        }
        .task {
            // Watchdog timer - if view doesn't load in 10 seconds, show error
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            if isLoading {
                loadFailed = true
            }
        }
    }
}

// MARK: - Preview


// MARK: - Typealias for backward compatibility
typealias PeopleDiscoveryView = PeopleDiscoveryViewNew

#Preview {
    let view = PeopleDiscoveryViewNew()
    return view
}
