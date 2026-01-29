//
//  FollowingListView.swift
//  AMENAPP
//
//  Created by AI Assistant on 1/28/26.
//

import SwiftUI
import FirebaseAuth

/// View displaying who a user is following with real-time updates
struct FollowingListView: View {
    let userId: String
    let isCurrentUser: Bool
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var followService = FollowService.shared
    
    @State private var following: [UserBasicInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    
    var filteredFollowing: [UserBasicInfo] {
        if searchText.isEmpty {
            return following
        }
        return following.filter { user in
            user.displayName.localizedCaseInsensitiveContains(searchText) ||
            user.username.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if following.isEmpty {
                    emptyStateView
                } else {
                    followingList
                }
            }
            .navigationTitle("Following")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .searchable(text: $searchText, prompt: "Search following")
            .task {
                await loadFollowing()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading following...")
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(.secondary)
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            
            Text("Error")
                .font(.custom("OpenSans-Bold", size: 20))
            
            Text(message)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                Task { await loadFollowing() }
            } label: {
                Text("Try Again")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.blue)
                    )
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("Not following anyone")
                .font(.custom("OpenSans-Bold", size: 18))
            
            Text(isCurrentUser ? "Find people to follow to see their content" : "This user isn't following anyone yet")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private var followingList: some View {
        List {
            ForEach(filteredFollowing) { user in
                FollowingRow(
                    user: user,
                    isCurrentUser: isCurrentUser,
                    onUnfollow: {
                        Task { await unfollowUser(user) }
                    }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }
    
    // MARK: - Data Loading
    
    @MainActor
    private func loadFollowing() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let followingIds = try await followService.fetchFollowingIds(userId: userId)
            
            // Fetch user details for each person being followed
            var followingDetails: [UserBasicInfo] = []
            
            for followedUserId in followingIds {
                if let userInfo = try? await followService.fetchUserBasicInfo(userId: followedUserId) {
                    followingDetails.append(userInfo)
                }
            }
            
            following = followingDetails.sorted { $0.displayName < $1.displayName }
            
            print("✅ Loaded \(following.count) following")
            
        } catch {
            print("❌ Error loading following: \(error)")
            errorMessage = "Failed to load following. Please try again."
        }
        
        isLoading = false
    }
    
    @MainActor
    private func unfollowUser(_ user: UserBasicInfo) async {
        // Optimistic update
        following.removeAll { $0.id == user.id }
        
        do {
            try await followService.unfollowUser(userId: user.id)
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            print("✅ Unfollowed: \(user.displayName)")
            
        } catch {
            print("❌ Error unfollowing user: \(error)")
            
            // Rollback on error
            await loadFollowing()
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }
}

// MARK: - Following Row

struct FollowingRow: View {
    let user: UserBasicInfo
    let isCurrentUser: Bool
    let onUnfollow: () -> Void
    
    @State private var showUnfollowAlert = false
    @State private var followsYouBack = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Group {
                if let profileImageURL = user.profileImageURL,
                   let url = URL(string: profileImageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            avatarPlaceholder
                        }
                    }
                } else {
                    avatarPlaceholder
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(user.displayName)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                    
                    if followsYouBack {
                        Text("• Follows you")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text("@\(user.username)")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Unfollow Button (only for current user)
            if isCurrentUser {
                Button {
                    showUnfollowAlert = true
                } label: {
                    Text("Following")
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.1))
                        )
                }
            }
        }
        .padding(.vertical, 8)
        .alert("Unfollow \(user.displayName)?", isPresented: $showUnfollowAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Unfollow", role: .destructive) {
                onUnfollow()
            }
        } message: {
            Text("You can always follow them again later.")
        }
        .task {
            // Check if this user follows back
            if isCurrentUser {
                followsYouBack = await checkFollowsBack(user.id)
            }
        }
    }
    
    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.black)
            .overlay(
                Text(user.initials)
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.white)
            )
    }
    
    private func checkFollowsBack(_ userId: String) async -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return false
        }
        
        do {
            let followerIds = try await FollowService.shared.fetchFollowerIds(userId: currentUserId)
            return followerIds.contains(userId)
        } catch {
            return false
        }
    }
}

#Preview {
    FollowingListView(
        userId: "sample-user-id",
        isCurrentUser: true
    )
}
