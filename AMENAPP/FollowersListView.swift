//
//  FollowersListView.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//

import SwiftUI
import FirebaseAuth

/// View for displaying followers or following lists
struct SocialFollowersListView: View {
    enum ListType {
        case followers
        case following
        
        var title: String {
            switch self {
            case .followers: return "Followers"
            case .following: return "Following"
            }
        }
    }
    
    let userId: String
    let listType: ListType
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var socialService = SocialService.shared
    @StateObject private var followService = FollowService.shared
    @State private var users: [UserModel] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Use white background to match ProfileView
                Color.white
                    .ignoresSafeArea()
                
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(1.2)
                        
                        Text("Loading...")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.secondary)
                    }
                } else if users.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(users) { user in
                                SocialUserRowView(user: user)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                
                                if user.id != users.last?.id {
                                    Divider()
                                        .background(Color.black.opacity(0.1))
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle(listType.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.black.opacity(0.5))
                    }
                }
            }
            .task {
                await loadUsers()
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: listType == .followers ? "person.2.slash" : "person.2")
                .font(.system(size: 60))
                .foregroundStyle(.black.opacity(0.3))
            
            Text(listType == .followers ? "No Followers Yet" : "Not Following Anyone")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.black)
            
            Text(listType == .followers ? 
                 "When people follow you, they'll appear here" :
                 "Start following people to see them here")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 60)
    }
    
    private func loadUsers() async {
        isLoading = true
        
        print("📥 Loading \(listType == .followers ? "followers" : "following") for user: \(userId)")
        
        do {
            switch listType {
            case .followers:
                users = try await socialService.fetchFollowers(for: userId)
                print("✅ Loaded \(users.count) followers")
            case .following:
                users = try await socialService.fetchFollowing(for: userId)
                print("✅ Loaded \(users.count) following")
            }
        } catch {
            print("❌ Failed to load users: \(error)")
            users = []
        }
        
        isLoading = false
    }
}

/// Row view for displaying a user in the list
private struct SocialUserRowView: View {
    let user: UserModel
    
    @StateObject private var followService = FollowService.shared
    @State private var isFollowing = false
    @State private var isLoading = false
    
    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    
    var isCurrentUser: Bool {
        guard let userId = user.id, let currentUserId = currentUserId else {
            return false
        }
        return userId == currentUserId
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Profile Picture
            avatarView
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.black)
                
                Text("@\(user.username)")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.black.opacity(0.5))
                
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.black.opacity(0.6))
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Follow Button (hide if viewing your own profile)
            if !isCurrentUser {
                followButton
            }
        }
        .task {
            await checkFollowStatus()
        }
    }
    
    @ViewBuilder
    private var avatarView: some View {
        if let imageURL = user.profileImageURL,
           !imageURL.isEmpty,
           let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                case .failure, .empty:
                    avatarPlaceholder
                @unknown default:
                    avatarPlaceholder
                }
            }
        } else {
            avatarPlaceholder
        }
    }
    
    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.black)
            .frame(width: 56, height: 56)
            .overlay(
                Text(user.initials)
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(.white)
            )
    }
    
    private var followButton: some View {
        Button {
            toggleFollow()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: isFollowing ? .black : .white))
                        .scaleEffect(0.8)
                } else {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.custom("OpenSans-Bold", size: 14))
                }
            }
            .foregroundStyle(isFollowing ? .black : .white)
            .frame(width: 90, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isFollowing ? Color.clear : Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.black, lineWidth: isFollowing ? 1.5 : 0)
                    )
            )
        }
        .disabled(isLoading)
    }
    
    private func checkFollowStatus() async {
        guard let userId = user.id else { return }
        isFollowing = await followService.isFollowing(userId: userId)
    }
    
    private func toggleFollow() {
        guard let userId = user.id else { return }
        
        // Prevent double-tapping
        guard !isLoading else {
            print("⚠️ Already processing follow action")
            return
        }
        
        isLoading = true
        
        // Store the current state to revert on error
        let originalFollowingState = isFollowing
        
        // Optimistically update UI
        isFollowing.toggle()
        
        Task {
            do {
                if originalFollowingState {
                    try await followService.unfollowUser(userId: userId)
                    print("✅ Unfollowed @\(user.username)")
                } else {
                    try await followService.followUser(userId: userId)
                    print("✅ Followed @\(user.username)")
                }
                
                // Success - UI is already updated
                await MainActor.run {
                    isLoading = false
                }
                
            } catch {
                print("❌ Failed to toggle follow: \(error)")
                
                // Revert UI on error
                await MainActor.run {
                    isFollowing = originalFollowingState
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    SocialFollowersListView(userId: "sample-user-id", listType: .followers)
}
