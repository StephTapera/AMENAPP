//
//  SpotlightView.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//

import SwiftUI

struct SpotlightView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedCategory: SpotlightCategory = .all
    
    enum SpotlightCategory: String, CaseIterable {
        case all = "All"
        case creators = "Creators"
        case innovators = "Innovators"
        case leaders = "Leaders"
        case newcomers = "Newcomers"
        
        var icon: String {
            switch self {
            case .all: return "star.fill"
            case .creators: return "paintbrush.fill"
            case .innovators: return "lightbulb.fill"
            case .leaders: return "crown.fill"
            case .newcomers: return "sparkles"
            }
        }
        
        var color: Color {
            switch self {
            case .all: return .yellow
            case .creators: return .purple
            case .innovators: return .orange
            case .leaders: return .blue
            case .newcomers: return .green
            }
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
                                ForEach(SpotlightCategory.allCases, id: \.self) { category in
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedCategory = category
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
                    VStack(spacing: 16) {
                        SpotlightMemberCard(
                            name: "Dr. Sarah Chen",
                            handle: "@sarahchen",
                            bio: "AI researcher exploring the intersection of faith and technology. Building ethical AI solutions.",
                            category: .innovators,
                            stats: (posts: 156, followers: "2.3K", engagement: "94%"),
                            avatarColor: .blue
                        )
                        
                        SpotlightMemberCard(
                            name: "Pastor David Martinez",
                            handle: "@pastordavid",
                            bio: "Leading digital ministry initiatives. Helping churches embrace technology while staying rooted in faith.",
                            category: .leaders,
                            stats: (posts: 234, followers: "5.1K", engagement: "98%"),
                            avatarColor: .purple
                        )
                        
                        SpotlightMemberCard(
                            name: "Emily Rodriguez",
                            handle: "@emilyrodriguez",
                            bio: "Content creator sharing daily devotionals and testimonies. Passionate about encouraging others.",
                            category: .creators,
                            stats: (posts: 412, followers: "8.7K", engagement: "96%"),
                            avatarColor: .pink
                        )
                        
                        SpotlightMemberCard(
                            name: "Michael Thompson",
                            handle: "@mikethompson",
                            bio: "Just joined! Software engineer looking to connect faith and code. Learning and growing.",
                            category: .newcomers,
                            stats: (posts: 12, followers: "48", engagement: "89%"),
                            avatarColor: .green
                        )
                    }
                    .padding(.horizontal)
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
        }
    }
}

struct SpotlightMemberCard: View {
    let name: String
    let handle: String
    let bio: String
    let category: SpotlightView.SpotlightCategory
    let stats: (posts: Int, followers: String, engagement: String)
    let avatarColor: Color
    
    @State private var isFollowing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                // Avatar
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
                        Text(String(name.prefix(2)))
                            .font(.custom("OpenSans-Bold", size: 22))
                            .foregroundStyle(.white)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.custom("OpenSans-Bold", size: 18))
                            .foregroundStyle(.primary)
                        
                        // Verified badge
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.blue)
                    }
                    
                    Text(handle)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                    
                    // Category badge
                    HStack(spacing: 4) {
                        Image(systemName: category.icon)
                            .font(.system(size: 10, weight: .bold))
                        
                        Text(category.rawValue)
                            .font(.custom("OpenSans-Bold", size: 11))
                    }
                    .foregroundStyle(category.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(category.color.opacity(0.15))
                    )
                }
                
                Spacer()
            }
            
            // Bio
            Text(bio)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary)
                .lineSpacing(4)
            
            // Stats
            HStack(spacing: 24) {
                StatItem(label: "Posts", value: "\(stats.posts)")
                StatItem(label: "Followers", value: stats.followers)
                StatItem(label: "Engagement", value: stats.engagement)
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
