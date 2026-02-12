//
//  SpotlightView.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//

import SwiftUI

struct SpotlightView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var trendingService = TrendingService.shared
    @State private var selectedCategory: SpotlightUser.SpotlightCategory = .all
    
    var filteredUsers: [SpotlightUser] {
        trendingService.spotlightUsers.filter { user in
            selectedCategory == .all || user.category == selectedCategory
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Community Spotlight")
                                    .font(.custom("OpenSans-Bold", size: 32))
                                    .foregroundStyle(.primary)
                                
                                Text("Featured members making an impact")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            ZStack {
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Color.yellow.opacity(0.3),
                                                Color.orange.opacity(0.1)
                                            ],
                                            center: .center,
                                            startRadius: 5,
                                            endRadius: 30
                                        )
                                    )
                                    .frame(width: 60, height: 60)
                                
                                Image(systemName: "star.fill")
                                    .font(.system(size: 40, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.yellow, .orange],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                        }
                        
                        // Category filter
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(SpotlightUser.SpotlightCategory.allCases, id: \.self) { category in
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedCategory = category
                                        }
                                        Task {
                                            try? await trendingService.fetchSpotlightUsers(category: category)
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: category.icon)
                                                .font(.system(size: 12, weight: .semibold))
                                            
                                            Text(category.rawValue)
                                                .font(.custom("OpenSans-SemiBold", size: 13))
                                        }
                                        .foregroundStyle(selectedCategory == category ? .white : category.color)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(
                                                    selectedCategory == category ?
                                                        category.color :
                                                        category.color.opacity(0.12)
                                                )
                                                .shadow(
                                                    color: selectedCategory == category ? category.color.opacity(0.3) : .clear,
                                                    radius: 6,
                                                    y: 3
                                                )
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Spotlighted members
                    if trendingService.isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Finding amazing community members...")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if filteredUsers.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("No spotlight users yet")
                                .font(.custom("OpenSans-Bold", size: 18))
                            Text("Be active in the community to get featured!")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        VStack(spacing: 16) {
                            ForEach(filteredUsers) { user in
                                SpotlightMemberCard(user: user)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.gray.opacity(0.3))
                    }
                }
            }
            .task {
                // Fetch spotlight users when view appears
                try? await trendingService.fetchSpotlightUsers(category: selectedCategory)
            }
        }
    }
}

struct SpotlightMemberCard: View {
    let user: SpotlightUser
    
    @State private var isFollowing = false
    
    private var avatarColor: Color {
        user.category.color
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                // Avatar with profile image or initials
                if let profileImageURL = user.profileImageURL, let url = URL(string: profileImageURL) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                    } placeholder: {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [avatarColor, avatarColor.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)
                            .overlay(
                                Text(String(user.name.prefix(2)))
                                    .font(.custom("OpenSans-Bold", size: 22))
                                    .foregroundStyle(.white)
                            )
                    }
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [avatarColor, avatarColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .overlay(
                            Text(String(user.name.prefix(2)))
                                .font(.custom("OpenSans-Bold", size: 22))
                                .foregroundStyle(.white)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(user.name)
                            .font(.custom("OpenSans-Bold", size: 18))
                            .foregroundStyle(.primary)
                        
                        // Verified badge
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    Text(user.username)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                    
                    // Category badge
                    HStack(spacing: 4) {
                        Image(systemName: user.category.icon)
                            .font(.system(size: 10, weight: .bold))
                        
                        Text(user.category.rawValue)
                            .font(.custom("OpenSans-Bold", size: 11))
                    }
                    .foregroundStyle(user.category.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(user.category.color.opacity(0.15))
                    )
                }
                
                Spacer()
            }
            
            // Bio
            Text(user.bio)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary)
                .lineSpacing(4)
            
            // Stats
            HStack(spacing: 24) {
                StatItem(label: "Posts", value: "\(user.stats.posts)")
                StatItem(label: "Followers", value: user.stats.followers)
                StatItem(label: "Engagement", value: user.stats.engagement)
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isFollowing.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if !isFollowing {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text(isFollowing ? "Following" : "Follow")
                            .font(.custom("OpenSans-Bold", size: 14))
                    }
                    .foregroundStyle(isFollowing ? Color.primary : Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isFollowing ? Color.clear : Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isFollowing ? Color.gray.opacity(0.3) : Color.clear, lineWidth: 1)
                            )
                    )
                }
                
                Button {
                    // View profile
                } label: {
                    Text("View Profile")
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                        )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
    }
}

struct StatItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(.primary)
            
            Text(label)
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SpotlightView()
}
