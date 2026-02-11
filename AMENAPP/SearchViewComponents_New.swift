//
//  SearchViewComponents.swift
//  AMENAPP
//
//  Redesigned with black & white glassmorphic Threads-inspired design
//  Production-ready with Algolia search integration
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Main Discover People View

struct DiscoverPeopleView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchService = UserSearchService.shared
    @StateObject private var followService = FollowService.shared
    
    @State private var searchText = ""
    @State private var selectedFilter: DiscoveryFilter = .all
    @State private var isSearching = false
    @State private var recentUsers: [FirebaseSearchUser] = []
    @State private var newUsers: [FirebaseSearchUser] = []
    
    enum DiscoveryFilter: String, CaseIterable {
        case all = "All"
        case new = "New"
        case active = "Active"
        case verified = "Verified"
        
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .new: return "clock"
            case .active: return "bolt.fill"
            case .verified: return "checkmark.seal.fill"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with back button
                    headerView
                    
                    // Search bar
                    searchBarView
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    
                    // Filter chips
                    filterChipsView
                        .padding(.top, 16)
                    
                    // Content
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 16) {
                            if isSearching {
                                loadingView
                            } else if !searchText.isEmpty {
                                searchResultsView
                            } else {
                                discoveryContentView
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationBarHidden(true)
            .task {
                await loadInitialData()
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 16) {
            Button {
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            }
            
            Text("Discover People")
                .font(.custom("OpenSans-Bold", size: 24))
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            Color(.systemBackground)
                .ignoresSafeArea(edges: .top)
        )
    }
    
    // MARK: - Search Bar
    
    private var searchBarView: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            
            TextField("Search people...", text: $searchText)
                .font(.custom("OpenSans-Regular", size: 16))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: searchText) { _, newValue in
                    Task {
                        await performSearch(query: newValue)
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
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
    
    // MARK: - Filter Chips
    
    private var filterChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(DiscoveryFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        filter: filter,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedFilter = filter
                        }
                        Task {
                            await applyFilter(filter)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Discovery Content
    
    @ViewBuilder
    private var discoveryContentView: some View {
        if selectedFilter == .new && !newUsers.isEmpty {
            newUsersSection
        } else {
            recentUsersSection
        }
    }
    
    private var newUsersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("New Members")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(newUsers.count) users")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            
            ForEach(newUsers) { user in
                NavigationLink {
                    UserProfileView(userId: user.id)
                } label: {
                    ThreadsStyleUserCard(user: user)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var recentUsersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(headerTitle)
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if !recentUsers.isEmpty {
                    Text("\(recentUsers.count) users")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            
            ForEach(recentUsers) { user in
                NavigationLink {
                    UserProfileView(userId: user.id)
                } label: {
                    ThreadsStyleUserCard(user: user)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var headerTitle: String {
        switch selectedFilter {
        case .all: return "Suggested"
        case .new: return "New Members"
        case .active: return "Active Users"
        case .verified: return "Verified Users"
        }
    }
    
    // MARK: - Search Results
    
    private var searchResultsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if searchService.searchResults.isEmpty {
                noResultsView
            } else {
                HStack {
                    Text("\(searchService.searchResults.count) results")
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                }
                
                ForEach(searchService.searchResults) { user in
                    NavigationLink {
                        UserProfileView(userId: user.id)
                    } label: {
                        ThreadsStyleUserCard(user: user)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No users found")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
            
            Text("Try a different search term")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ForEach(0..<5) { _ in
                UserCardSkeleton()
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadInitialData() async {
        do {
            // Load recent users (all users sorted by creation date)
            let snapshot = try await Firestore.firestore()
                .collection("users")
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
                .getDocuments()
            
            recentUsers = snapshot.documents.compactMap { doc in
                try? doc.data(as: FirebaseSearchUser.self)
            }
            
            // Load new users (joined in last 7 days)
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            let newSnapshot = try await Firestore.firestore()
                .collection("users")
                .whereField("createdAt", isGreaterThan: sevenDaysAgo)
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
                .getDocuments()
            
            newUsers = newSnapshot.documents.compactMap { doc in
                try? doc.data(as: FirebaseSearchUser.self)
            }
            
            print("✅ Loaded \(recentUsers.count) recent users and \(newUsers.count) new users")
            
        } catch {
            print("❌ Error loading users: \(error)")
        }
    }
    
    private func performSearch(query: String) async {
        guard !query.isEmpty else {
            isSearching = false
            return
        }
        
        isSearching = true
        
        // Debounce search
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        do {
            // Use Algolia via UserSearchService
            _ = try await searchService.searchUsers(query: query, searchType: .both)
            
        } catch {
            print("❌ Search error: \(error)")
        }
        
        isSearching = false
    }
    
    private func applyFilter(_ filter: DiscoveryFilter) async {
        do {
            var query = Firestore.firestore().collection("users")
            
            switch filter {
            case .all:
                query = query.order(by: "createdAt", descending: true)
            case .new:
                let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                query = query
                    .whereField("createdAt", isGreaterThan: sevenDaysAgo)
                    .order(by: "createdAt", descending: true)
            case .active:
                // Users who posted or interacted recently
                query = query.order(by: "lastActiveAt", descending: true)
            case .verified:
                query = query
                    .whereField("isVerified", isEqualTo: true)
                    .order(by: "followersCount", descending: true)
            }
            
            let snapshot = try await query.limit(to: 20).getDocuments()
            
            let users = snapshot.documents.compactMap { doc in
                try? doc.data(as: FirebaseSearchUser.self)
            }
            
            await MainActor.run {
                recentUsers = users
            }
            
        } catch {
            print("❌ Filter error: \(error)")
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let filter: DiscoverPeopleView.DiscoveryFilter
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.system(size: 12, weight: .semibold))
                
                Text(filter.rawValue)
                    .font(.custom("OpenSans-Bold", size: 14))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? Color.primary : Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(isSelected ? 0 : 0.12), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Threads-Style User Card

struct ThreadsStyleUserCard: View {
    let user: FirebaseSearchUser
    @StateObject private var followService = FollowService.shared
    @State private var isFollowing = false
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Profile Photo
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                if let photoURL = user.profileImageURL, !photoURL.isEmpty {
                    AsyncImage(url: URL(string: photoURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                        default:
                            Text(user.initials)
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.primary)
                        }
                    }
                } else {
                    Text(user.initials)
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.primary)
                }
                
                // Verification badge
                if user.isVerified {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.blue)
                                .background(
                                    Circle()
                                        .fill(Color(.systemBackground))
                                        .frame(width: 16, height: 16)
                                )
                        }
                    }
                    .frame(width: 48, height: 48)
                }
            }
            
            // User Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(user.displayName)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                
                Text("@\(user.username)")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                if !user.bio.isEmpty {
                    Text(user.bio)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
            
            // Follow Button
            ThreadsFollowButton(isFollowing: $isFollowing, userId: user.id)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .task {
            await loadFollowStatus()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
    
    private func loadFollowStatus() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        isFollowing = await followService.isFollowing(userId: user.id)
    }
}

// MARK: - Threads-Style Follow Button

struct ThreadsFollowButton: View {
    @Binding var isFollowing: Bool
    let userId: String
    @StateObject private var followService = FollowService.shared
    @State private var isProcessing = false
    
    var body: some View {
        Button {
            guard !isProcessing else { return }
            handleFollowToggle()
        } label: {
            Text(isFollowing ? "Following" : "Follow")
                .font(.custom("OpenSans-Bold", size: 13))
                .foregroundStyle(isFollowing ? .primary : .white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isFollowing ? Color.clear : Color.primary)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(isFollowing ? 0.3 : 0), lineWidth: 1)
                )
                .opacity(isProcessing ? 0.6 : 1.0)
        }
        .disabled(isProcessing)
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFollowing)
    }
    
    private func handleFollowToggle() {
        isProcessing = true
        
        Task {
            do {
                if isFollowing {
                    try await followService.unfollowUser(userId: userId)
                } else {
                    try await followService.followUser(userId: userId)
                }
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isFollowing.toggle()
                    }
                    
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    
                    isProcessing = false
                }
                
            } catch {
                print("❌ Follow error: \(error)")
                await MainActor.run {
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - User Card Skeleton

struct UserCardSkeleton: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar skeleton
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 48, height: 48)
            
            VStack(alignment: .leading, spacing: 6) {
                // Name skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 16)
                
                // Username skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 80, height: 14)
                
                // Bio skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 180, height: 12)
            }
            
            Spacer()
            
            // Button skeleton
            Capsule()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 80, height: 32)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(
            .easeInOut(duration: 1.0)
            .repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Discover People Section (for Home/Search)

struct DiscoverPeopleSection: View {
    @StateObject private var searchService = UserSearchService.shared
    @State private var suggestedUsers: [FirebaseSearchUser] = []
    @State private var showFullDiscovery = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Let's Stay Connected")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.primary)
                    
                    Text("Discover believers to connect with")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    showFullDiscovery = true
                } label: {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.custom("OpenSans-Bold", size: 13))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 20)
            
            // Horizontal scroll of users
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(suggestedUsers.prefix(10)) { user in
                        CompactUserCard(user: user)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 12)
        .task {
            await loadSuggestedUsers()
        }
        .sheet(isPresented: $showFullDiscovery) {
            DiscoverPeopleView()
        }
    }
    
    private func loadSuggestedUsers() async {
        do {
            let snapshot = try await Firestore.firestore()
                .collection("users")
                .order(by: "createdAt", descending: true)
                .limit(to: 15)
                .getDocuments()
            
            suggestedUsers = snapshot.documents.compactMap { doc in
                try? doc.data(as: FirebaseSearchUser.self)
            }
            
        } catch {
            print("❌ Error loading suggested users: \(error)")
        }
    }
}

// MARK: - Compact User Card (for horizontal scroll)

struct CompactUserCard: View {
    let user: FirebaseSearchUser
    @StateObject private var followService = FollowService.shared
    @State private var isFollowing = false
    @State private var showProfile = false
    
    var body: some View {
        Button {
            showProfile = true
        } label: {
            VStack(spacing: 10) {
                // Profile Photo
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 64, height: 64)
                    
                    if let photoURL = user.profileImageURL, !photoURL.isEmpty {
                        AsyncImage(url: URL(string: photoURL)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(Circle())
                            default:
                                Text(user.initials)
                                    .font(.custom("OpenSans-Bold", size: 22))
                                    .foregroundStyle(.primary)
                            }
                        }
                    } else {
                        Text(user.initials)
                            .font(.custom("OpenSans-Bold", size: 22))
                            .foregroundStyle(.primary)
                    }
                    
                    if user.isVerified {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.blue)
                                    .background(
                                        Circle()
                                            .fill(Color(.systemBackground))
                                            .frame(width: 18, height: 18)
                                    )
                            }
                        }
                        .frame(width: 64, height: 64)
                    }
                }
                
                // User Info
                VStack(spacing: 2) {
                    Text(user.displayName)
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text("@\(user.username)")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                // Follow Button
                Button {
                    handleFollowToggle()
                } label: {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.custom("OpenSans-Bold", size: 12))
                        .foregroundStyle(isFollowing ? .primary : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isFollowing ? Color.clear : Color.primary)
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.primary.opacity(isFollowing ? 0.3 : 0), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .frame(width: 120)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .task {
            await loadFollowStatus()
        }
        .sheet(isPresented: $showProfile) {
            UserProfileView(userId: user.id)
        }
    }
    
    private func loadFollowStatus() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        isFollowing = await followService.isFollowing(userId: user.id)
    }
    
    private func handleFollowToggle() {
        Task {
            do {
                if isFollowing {
                    try await followService.unfollowUser(userId: user.id)
                } else {
                    try await followService.followUser(userId: user.id)
                }
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isFollowing.toggle()
                    }
                    
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                }
                
            } catch {
                print("❌ Follow error: \(error)")
            }
        }
    }
}

// MARK: - Extensions

extension FirebaseSearchUser {
    var initials: String {
        let components = displayName.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }
}

// MARK: - Preview

#Preview("Discover Section") {
    DiscoverPeopleSection()
}

#Preview("Full Discovery") {
    DiscoverPeopleView()
}
