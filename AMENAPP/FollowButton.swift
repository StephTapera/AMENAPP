//
//  FollowButton.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//

import SwiftUI

/// A reusable follow/unfollow button component
struct SocialFollowButton: View {
    let userId: String
    let username: String
    
    @State private var isFollowing = false
    @State private var isLoading = false
    
    private let followService = FollowService.shared
    
    var body: some View {
        Button {
            handleFollowToggle()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: isFollowing ? .gray : .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: isFollowing ? "person.fill.checkmark" : "person.fill.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                }
                
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
        .disabled(isLoading)
        .task {
            await checkFollowStatus()
        }
    }
    
    private func checkFollowStatus() async {
        isFollowing = await followService.isFollowing(userId: userId)
    }
    
    private func handleFollowToggle() {
        isLoading = true
        
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
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    print("❌ Follow/Unfollow error: \(error)")
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        SocialFollowButton(userId: "sample-user-id", username: "johndoe")
    }
}
