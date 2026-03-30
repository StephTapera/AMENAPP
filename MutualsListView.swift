//
//  MutualsListView.swift
//  AMENAPP
//
//  Sheet showing the full list of mutual connections.
//  Warm, community-oriented copy. Dark glassmorphic style.
//

import SwiftUI
import FirebaseAuth

struct MutualsListView: View {
    let mutuals: [MutualConnection]
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var followService = FollowService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if mutuals.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .navigationTitle("People you both know")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.black)
        .presentationDragIndicator(.visible)
    }

    // MARK: - List

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(mutuals) { mutual in
                    MutualsRowView(mutual: mutual, followService: followService)
                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.leading, 72)
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.3))
            Text("No mutual connections yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Text("When you and this person both follow the same people, they'll appear here.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Row

private struct MutualsRowView: View {
    let mutual: MutualConnection
    @ObservedObject var followService: FollowService
    @State private var isFollowInProgress = false

    private var isAlreadyFollowing: Bool {
        followService.following.contains(mutual.id)
    }

    private var isOwnProfile: Bool {
        Auth.auth().currentUser?.uid == mutual.id
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            NavigationLink(destination: UserProfileView(userId: mutual.id)) {
                MutualsCircleAvatar(url: mutual.profilePhotoURL, size: 44)
            }
            .buttonStyle(.plain)

            // Name + subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(mutual.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Follows you both")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            // Follow button (only for users the viewer doesn't already follow)
            if !isOwnProfile {
                followButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var followButton: some View {
        Button {
            guard !isFollowInProgress else { return }
            isFollowInProgress = true
            Task {
                defer { isFollowInProgress = false }
                if isAlreadyFollowing {
                    try? await followService.unfollowUser(userId: mutual.id)
                } else {
                    try? await followService.followUser(userId: mutual.id)
                }
            }
        } label: {
            Text(isAlreadyFollowing ? "Following" : "Follow")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isAlreadyFollowing ? .black : .white)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isAlreadyFollowing ? Color(white: 0.9) : Color.white.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(isAlreadyFollowing ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
        }
        .disabled(isFollowInProgress)
    }
}
