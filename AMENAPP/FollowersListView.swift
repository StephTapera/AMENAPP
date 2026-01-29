//
//  FollowersListView.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//

import SwiftUI

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
    @State private var users: [UserModel] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.08)
                    .ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .orange))
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
                                        .background(Color.white.opacity(0.1))
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.7))
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
                .foregroundStyle(.white.opacity(0.4))
            
            Text(listType == .followers ? "No Followers Yet" : "Not Following Anyone")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.white)
            
            Text(listType == .followers ? 
                 "When people follow you, they'll appear here" :
                 "Start following people to see them here")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    private func loadUsers() async {
        isLoading = true
        
        do {
            switch listType {
            case .followers:
                users = try await socialService.fetchFollowers(for: userId)
            case .following:
                users = try await socialService.fetchFollowing(for: userId)
            }
        } catch {
            print("❌ Failed to load users: \(error)")
        }
        
        isLoading = false
    }
}

/// Row view for displaying a user in the list
private struct SocialUserRowView: View {
    let user: UserModel
    
    var body: some View {
        HStack(spacing: 16) {
            // Profile Picture
            if let imageURL = user.profileImageURL,
               let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Text(user.initials)
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.white)
                        )
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.6), Color(red: 1.0, green: 0.6, blue: 0.2).opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(user.initials)
                            .font(.custom("OpenSans-Bold", size: 20))
                            .foregroundStyle(.white)
                    )
            }
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.white)
                
                Text("@\(user.username)")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                
                if let bio = user.bio {
                    Text(bio)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Follow Button
            if let userId = user.id {
                SocialFollowButton(userId: userId, username: user.username)
            }
        }
    }
}

#Preview {
    SocialFollowersListView(userId: "sample-user-id", listType: .followers)
}
