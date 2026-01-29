//
//  FollowerIntegrationHelper.swift
//  AMENAPP
//
//  Created by Steph on 1/28/26.
//
//  Helper functions and extensions for quick follower/following integration
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Quick Integration Extensions

extension View {
    /// Adds a floating follow button overlay to any view
    func withFollowButton(for userId: String) -> some View {
        self.overlay(alignment: .bottomTrailing) {
            FollowButtonWrapper(userId: userId)
                .padding()
        }
    }
    
    /// Shows follow requests badge if there are pending requests
    func withFollowRequestsBadge() -> some View {
        self.modifier(FollowRequestsBadgeModifier())
    }
}

// MARK: - Follow Button Wrapper

/// Simple follow button that accepts a binding
struct QuickFollowButton: View {
    @Binding var isFollowing: Bool
    
    var body: some View {
        Button {
            isFollowing.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isFollowing ? "person.fill.checkmark" : "person.fill.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                
                Text(isFollowing ? "Following" : "Follow")
                    .font(.custom("OpenSans-Bold", size: 14))
            }
            .foregroundStyle(isFollowing ? Color.gray : Color.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Group {
                    if isFollowing {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange, Color(red: 1.0, green: 0.6, blue: 0.2)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }
            )
        }
    }
}

/// Wrapper for the follow button that manages state internally
struct FollowButtonWrapper: View {
    let userId: String
    @State private var isFollowing = false
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(width: 100, height: 36)
            } else {
                QuickFollowButton(isFollowing: $isFollowing)
                    .onChange(of: isFollowing) { oldValue, newValue in
                        Task {
                            await handleFollowToggle(newValue)
                        }
                    }
            }
        }
        .task {
            await loadFollowState()
        }
    }
    
    private func handleFollowToggle(_ shouldFollow: Bool) async {
        do {
            if shouldFollow {
                try await FollowerQuickActions.followUser(userId: userId)
            } else {
                try await FollowerQuickActions.unfollowUser(userId: userId)
            }
        } catch {
            print("❌ Follow/unfollow failed: \(error)")
            // Revert state on error
            isFollowing = !shouldFollow
        }
    }
    
    private func loadFollowState() async {
        isFollowing = await FollowerQuickActions.isFollowing(userId: userId)
        isLoading = false
    }
}

// MARK: - Follow Requests Badge

struct FollowRequestsBadgeModifier: ViewModifier {
    @StateObject private var viewModel = FollowRequestsBadgeViewModel()
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if viewModel.pendingCount > 0 {
                    ZStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 20, height: 20)
                        
                        Text("\(viewModel.pendingCount)")
                            .font(.custom("OpenSans-Bold", size: 11))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 8, y: -8)
                }
            }
            .task {
                await viewModel.loadPendingCount()
            }
    }
}

@MainActor
class FollowRequestsBadgeViewModel: ObservableObject {
    @Published var pendingCount = 0
    private let db = Firestore.firestore()
    
    func loadPendingCount() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let snapshot = try await db.collection("followRequests")
                .whereField("toUserId", isEqualTo: currentUserId)
                .whereField("status", isEqualTo: "pending")
                .getDocuments()
            
            pendingCount = snapshot.documents.count
        } catch {
            print("❌ Failed to load pending requests count: \(error)")
        }
    }
}

// MARK: - Settings Integration Helper

struct FollowerSettingsSection: View {
    @State private var showPeopleDiscovery = false
    @State private var showFollowRequests = false
    @State private var showAnalytics = false
    
    private enum ActiveSheet: Identifiable {
        case people, requests, analytics
        var id: Int { hashValue }
    }
    @State private var activeSheet: ActiveSheet?
    
    var body: some View {
        Section {
            Button {
                activeSheet = .people
            } label: {
                HStack {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.blue)
                        .frame(width: 32)
                    
                    Text("Discover People")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Button {
                activeSheet = .requests
            } label: {
                HStack {
                    Image(systemName: "person.badge.clock")
                        .font(.system(size: 18))
                        .foregroundStyle(.purple)
                        .frame(width: 32)
                    
                    Text("Follow Requests")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .withFollowRequestsBadge()
            
            Button {
                activeSheet = .analytics
            } label: {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 18))
                        .foregroundStyle(.green)
                        .frame(width: 32)
                    
                    Text("Follower Analytics")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
        } header: {
            Text("SOCIAL & CONNECTIONS")
                .font(.custom("OpenSans-Bold", size: 12))
        }
        .sheet(item: $activeSheet) { sheet in
            createSheetContent(for: sheet)
        }
    }
    
    private func createSheetContent(for sheet: ActiveSheet) -> AnyView {
        switch sheet {
        case .people:
            return AnyView(PeopleDiscoveryView())
        case .requests:
            return AnyView(FollowRequestsView())
        case .analytics:
            return AnyView(FollowersAnalyticsView())
        }
    }
}

// MARK: - Quick Stats Widget

/// Shows follower/following stats in a compact card
struct FollowerStatsWidget: View {
    let userId: String
    @State private var stats: (followers: Int, following: Int) = (0, 0)
    @State private var showFollowersList = false
    @State private var showFollowingList = false
    
    var body: some View {
        HStack(spacing: 24) {
            Button {
                showFollowersList = true
            } label: {
                VStack(spacing: 4) {
                    Text("\(formatCount(stats.followers))")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.black)
                    
                    Text("Followers")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Divider()
                .frame(height: 40)
            
            Button {
                showFollowingList = true
            } label: {
                VStack(spacing: 4) {
                    Text("\(formatCount(stats.following))")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.black)
                    
                    Text("Following")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        )
        .sheet(isPresented: $showFollowersList) {
            createFollowersListView()
        }
        .sheet(isPresented: $showFollowingList) {
            createFollowingListView()
        }
        .task {
            await loadStats()
        }
    }
    
    private func createFollowersListView() -> some View {
        FollowersListView(userId: userId, type: .followers)
    }
    
    private func createFollowingListView() -> some View {
        FollowersListView(userId: userId, type: .following)
    }
    
    private func loadStats() async {
        do {
            let followService = FollowService.shared
            stats = try await followService.getFollowStats(userId: userId)
        } catch {
            print("❌ Failed to load stats: \(error)")
        }
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1000000 {
            return String(format: "%.1fM", Double(count) / 1000000.0)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else {
            return "\(count)"
        }
    }
}

// MARK: - Search Integration Helper

/// Add to SearchView to show people search
struct PeopleSearchResultsView: View {
    let searchQuery: String
    @StateObject private var viewModel = PeopleSearchViewModel()
    
    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                ProgressView()
                    .padding()
            } else if viewModel.users.isEmpty {
                Text("No people found for '\(searchQuery)'")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.users) { user in
                        NavigationLink(destination: UserProfileView(userId: user.id ?? "")) {
                            UserDiscoveryCard(user: user)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(20)
            }
        }
        .task(id: searchQuery) {
            await viewModel.search(query: searchQuery)
        }
    }
}

@MainActor
class PeopleSearchViewModel: ObservableObject {
    @Published var users: [UserModel] = []
    @Published var isLoading = false
    
    private let db = Firestore.firestore()
    
    func search(query: String) async {
        guard !query.isEmpty else {
            users = []
            return
        }
        
        isLoading = true
        
        do {
            let lowercaseQuery = query.lowercased()
            
            let snapshot = try await db.collection("users")
                .whereField("username", isGreaterThanOrEqualTo: lowercaseQuery)
                .whereField("username", isLessThanOrEqualTo: lowercaseQuery + "\u{f8ff}")
                .limit(to: 20)
                .getDocuments()
            
            users = snapshot.documents.compactMap { try? $0.data(as: UserModel.self) }
            
            // Also search by display name if username search didn't yield results
            if users.count < 5 {
                let nameSnapshot = try await db.collection("users")
                    .whereField("displayName", isGreaterThanOrEqualTo: query)
                    .whereField("displayName", isLessThanOrEqualTo: query + "\u{f8ff}")
                    .limit(to: 20)
                    .getDocuments()
                
                let nameResults = nameSnapshot.documents.compactMap { try? $0.data(as: UserModel.self) }
                
                for user in nameResults {
                    if !users.contains(where: { $0.id == user.id }) {
                        users.append(user)
                    }
                }
            }
            
        } catch {
            print("❌ Search failed: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - Navigation Helper

/// Centralized navigation for follower features
struct FollowerNavigationHelper {
    /// Navigate to user profile
    static func navigateToProfile(userId: String) -> some View {
        UserProfileView(userId: userId)
    }
    
    /// Navigate to followers list
    static func navigateToFollowers(userId: String) -> some View {
        FollowersListView(userId: userId, type: .followers)
    }
    
    /// Navigate to following list
    static func navigateToFollowing(userId: String) -> some View {
        FollowersListView(userId: userId, type: .following)
    }
    
    /// Navigate to people discovery
    static func navigateToPeopleDiscovery() -> some View {
        PeopleDiscoveryView()
    }
    
    /// Navigate to follow requests
    static func navigateToFollowRequests() -> some View {
        FollowRequestsView()
    }
    
    /// Navigate to analytics
    static func navigateToAnalytics() -> some View {
        FollowersAnalyticsView()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when someone follows/unfollows the current user
    static let followerCountChanged = Notification.Name("followerCountChanged")
    
    /// Posted when user follows/unfollows someone
    static let followingCountChanged = Notification.Name("followingCountChanged")
    
    /// Posted when a follow request is received
    static let followRequestReceived = Notification.Name("followRequestReceived")
    
    /// Posted when a follow request is accepted
    static let followRequestAccepted = Notification.Name("followRequestAccepted")
}

// MARK: - Quick Setup Functions

struct FollowerSystemSetup {
    /// Initialize follower system on app launch
    static func initialize() {
        let followService = FollowService.shared
        
        // Start real-time listeners for current user
        Task { @MainActor in
            await followService.loadCurrentUserFollowing()
            await followService.loadCurrentUserFollowers()
            followService.startListening()
            
            print("✅ Follower system initialized")
        }
    }
    
    /// Clean up on app termination
    static func cleanup() {
        let followService = FollowService.shared
        followService.stopListening()
        
        print("🔇 Follower system listeners stopped")
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension UserModel {
    static let sampleUsers: [UserModel] = [
        UserModel(
            id: "user-1",
            email: "john@example.com",
            displayName: "John Doe",
            username: "johndoe",
            bio: "Faith-driven developer",
            followersCount: 1234,
            followingCount: 567,
            postsCount: 89
        ),
        UserModel(
            id: "user-2",
            email: "jane@example.com",
            displayName: "Jane Smith",
            username: "janesmith",
            bio: "Spreading God's love",
            followersCount: 5678,
            followingCount: 890,
            postsCount: 234
        ),
        UserModel(
            id: "user-3",
            email: "bob@example.com",
            displayName: "Bob Wilson",
            username: "bobwilson",
            bio: "Pastor & author",
            followersCount: 12345,
            followingCount: 234,
            postsCount: 456
        )
    ]
}
#endif

// MARK: - Quick Actions

struct FollowerQuickActions {
    /// Quick follow a user
    static func followUser(userId: String) async throws {
        let service = FollowService.shared
        try await service.followUser(userId: userId)
        
        // Post notification
        NotificationCenter.default.post(name: .followingCountChanged, object: nil)
    }
    
    /// Quick unfollow a user
    static func unfollowUser(userId: String) async throws {
        let service = FollowService.shared
        try await service.unfollowUser(userId: userId)
        
        // Post notification
        NotificationCenter.default.post(name: .followingCountChanged, object: nil)
    }
    
    /// Check if following
    static func isFollowing(userId: String) async -> Bool {
        let service = FollowService.shared
        return await service.isFollowing(userId: userId)
    }
}

// MARK: - Usage Examples in Comments

/*
 
 USAGE EXAMPLES:
 
 1. Add Follow Button to Any View:
 
 ```swift
 VStack {
     Text("User Profile")
 }
 .withFollowButton(for: "user-id-123")

*/


