//
//  SuggestedUserRow.swift
//  AMENAPP
//
//  System 13: Suggested Follows
//  Row: avatar + name/username + reason pill(s) + follow button + dismiss.
//  Staggered entrance animation driven by `index`.
//  Integrates with FollowBurstCoordinator for friction UX.
//

import SwiftUI

struct SuggestedUserRow: View {
    let recommendation: RecommendedUsersAIService.UserRecommendation
    let index: Int
    let onFollowed: (() -> Void)?
    let onDismissed: (() -> Void)?

    @State private var isFollowing = false
    @State private var isInProgress = false
    @State private var appeared = false
    @State private var showFrictionConfirm = false

    @ObservedObject private var burstCoordinator = FollowBurstCoordinator.shared

    // Stagger delay: each row appears 60ms after the previous
    private var staggerDelay: Double { Double(index) * 0.06 }

    var body: some View {
        HStack(spacing: 12) {
            avatarView
            infoStack
            Spacer(minLength: 4)
            actionStack
        }
        .padding(.vertical, 8)
        // Staggered entrance: slide up + fade in
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82).delay(staggerDelay)) {
                appeared = true
            }
            isFollowing = FollowService.shared.following.contains(recommendation.id)
        }
        // Friction confirmation alert
        .alert("Follow this account?", isPresented: $showFrictionConfirm) {
            Button("Cancel", role: .cancel) { isInProgress = false }
            Button("Follow") { executeFollow() }
        } message: {
            Text("Thoughtful connections help keep AMEN a safe community.")
        }
    }

    // MARK: - Avatar

    private var avatarView: some View {
        CachedAsyncImage(
            url: recommendation.profileImageURL.flatMap { URL(string: $0) },
            size: CGSize(width: 96, height: 96),
            content: { image in
                image.resizable().scaledToFill()
            },
            placeholder: { initialsView }
        )
        .frame(width: 52, height: 52)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.12))
            .overlay(
                Text(String(recommendation.name.prefix(1)).uppercased())
                    .font(.systemScaled(20, weight: .semibold))
                    .foregroundStyle(.secondary)
            )
    }

    // MARK: - Info Stack (name + username + reason pills)

    private var infoStack: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(recommendation.name)
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(ProfileDesignTokens.textPrimary)
                .lineLimit(1)

            if !recommendation.username.isEmpty {
                Text("@\(recommendation.username)")
                    .font(.systemScaled(13))
                    .foregroundStyle(ProfileDesignTokens.textSecondary)
                    .lineLimit(1)
            }

            // Reason pills — up to 2
            if !reasonPills.isEmpty {
                HStack(spacing: 4) {
                    ForEach(reasonPills.prefix(2), id: \.self) { pill in
                        ReasonPillView(label: pill)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    /// Derive up to 2 user-facing reason labels from the recommendation.
    private var reasonPills: [String] {
        var pills: [String] = []

        if recommendation.mutualFriendCount > 0 {
            let label = recommendation.mutualFriendCount == 1
                ? "1 mutual"
                : "\(recommendation.mutualFriendCount) mutuals"
            pills.append(label)
        }

        if let first = recommendation.sharedInterests.first {
            pills.append(first)
        } else if !recommendation.matchReason.isEmpty {
            pills.append(recommendation.matchReason)
        }

        return pills
    }

    // MARK: - Action Stack (follow button + dismiss)

    private var actionStack: some View {
        VStack(spacing: 6) {
            followButton
            dismissButton
        }
    }

    private var followButton: some View {
        Button {
            guard !isInProgress, !isFollowing else { return }
            isInProgress = true

            let friction = burstCoordinator.frictionStateForNextFollow()

            switch friction {
            case .cooldown:
                // Blocked — show message via frictionState, no action
                isInProgress = false
            case .confirm:
                // Ask for explicit confirmation before proceeding
                showFrictionConfirm = true
            case .nudge, .clear:
                // Optional short delay for nudge state
                let delay: TimeInterval = friction == .nudge ? FollowSafetyThresholds.shared.frictionDelaySeconds : 0
                if delay > 0 {
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        executeFollow()
                    }
                } else {
                    executeFollow()
                }
            }
        } label: {
            Group {
                if isInProgress && !showFrictionConfirm {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 60, height: 30)
                } else if burstCoordinator.frictionState == .cooldown && !isFollowing {
                    // Show locked state visually during cooldown
                    Image(systemName: "hourglass")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                        .frame(width: 60, height: 30)
                } else {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.systemScaled(13, weight: .semibold))
                        .frame(width: 72, height: 30)
                }
            }
            .foregroundColor(isFollowing ? .secondary : .white)
            .background(
                Capsule()
                    .fill(isFollowing
                          ? Color.gray.opacity(0.15)
                          : burstCoordinator.frictionState == .cooldown && !isFollowing
                            ? Color.orange.opacity(0.12)
                            : Color.accentColor)
            )
        }
        .disabled(isFollowing || isInProgress || burstCoordinator.frictionState == .cooldown)
        .animation(.easeInOut(duration: 0.2), value: isFollowing)
        .animation(.easeInOut(duration: 0.2), value: burstCoordinator.frictionState)
    }

    private var dismissButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                onDismissed?()
            }
        } label: {
            Text("Not now")
                .font(.systemScaled(11))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Follow Execution

    private func executeFollow() {
        Task {
            do {
                try await FollowService.shared.followUser(userId: recommendation.id)
                isFollowing = true
                // Record in burst coordinator
                burstCoordinator.recordFollow(targetUserId: recommendation.id)
                onFollowed?()
            } catch {
                dlog("SuggestedUserRow follow failed: \(error)")
            }
            isInProgress = false
        }
    }
}

// MARK: - Reason Pill View

/// Small contextual pill explaining why a user was suggested.
/// Kept subtle — background, not loud badge style.
struct ReasonPillView: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.systemScaled(11, weight: .medium))
            .foregroundStyle(ProfileDesignTokens.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        Capsule()
                            .strokeBorder(ProfileDesignTokens.hairlineBorder, lineWidth: 0.5)
                    )
            )
    }
}
