//
//  SuggestedUserRow.swift
//  AMENAPP
//
//  System 13: Suggested Follows
//  Row: avatar + name/username + reason pill(s) + follow button + dismiss.
//  Staggered entrance animation driven by `index`.
//  Integrates with FollowBurstCoordinator for friction UX.
//
//  Consumes DisplaySuggestion (unified bridge type that works for both
//  SuggestedFollowsService smart-ranked results and RecommendedUsersAIService
//  fallback results).
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SuggestedUserRow: View {
    let recommendation: DisplaySuggestion
    let index: Int
    let onFollowed: (() -> Void)?
    let onDismissed: (() -> Void)?

    // P1 FIX: Use FollowStateManager for single source of truth so state is
    // consistent across all surfaces (discovery, feed, profile, suggestions).
    @State private var followState: FollowStateManager.FollowState = .notFollowing
    @State private var isInProgress = false
    @State private var appeared = false
    @State private var showFrictionConfirm = false

    @ObservedObject private var burstCoordinator = FollowBurstCoordinator.shared

    // Stagger delay: each row appears 60ms after the previous
    private var staggerDelay: Double { Double(index) * 0.06 }

    // Convenience shim — keeps follow guard readable
    private var isFollowing: Bool { followState.isFollowing }

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
            // Seed from FollowStateManager cache instantly (no Firestore round-trip)
            followState = FollowStateManager.shared.followStates[recommendation.id] ?? .notFollowing
        }
        .task {
            // Async-fetch authoritative state — handles "requested" for private accounts
            let state = await FollowStateManager.shared.getState(for: recommendation.id)
            withAnimation { followState = state }
        }
        // Listen for cross-surface follow state changes (follow from profile, feed, etc.)
        .onReceive(
            NotificationCenter.default.publisher(for: .followStateDidChange)
        ) { notification in
            guard let info = notification.userInfo,
                  let userId = info["userId"] as? String,
                  userId == recommendation.id,
                  let state = info["state"] as? FollowStateManager.FollowState else { return }
            withAnimation { followState = state }
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

            // Reason pills — primary reason always shown, up to 1 secondary
            reasonPillsView
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var reasonPillsView: some View {
        let pills = buildPills()
        if !pills.isEmpty {
            HStack(spacing: 4) {
                ForEach(pills.prefix(2), id: \.self) { pill in
                    ReasonPillView(label: pill)
                }
            }
        }
    }

    /// Returns primary reason + up to 1 secondary pill.
    private func buildPills() -> [String] {
        var pills: [String] = []

        // Primary reason from the ranking engine
        if !recommendation.primaryReason.isEmpty {
            pills.append(recommendation.primaryReason)
        }

        // One secondary pill (first secondary reason or mutual count)
        if let first = recommendation.secondaryReasons.first, !first.isEmpty {
            pills.append(first)
        } else if recommendation.mutualFriendCount > 0, pills.count < 2 {
            let label = recommendation.mutualFriendCount == 1
                ? "1 mutual"
                : "\(recommendation.mutualFriendCount) mutuals"
            pills.append(label)
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

    // MARK: - Follow Button (three-state: Follow / Requested / Following)

    private var followButton: some View {
        Button {
            // Tapping "Requested" cancels the pending request
            if followState == .requested {
                cancelRequest()
                return
            }
            guard !isInProgress, !isFollowing else { return }
            isInProgress = true

            let friction = burstCoordinator.frictionStateForNextFollow()

            switch friction {
            case .cooldown:
                isInProgress = false
            case .confirm:
                showFrictionConfirm = true
            case .nudge, .clear:
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
                        .tint(followState == .notFollowing ? .white : .primary)
                        .frame(width: 60, height: 30)
                } else if burstCoordinator.frictionState == .cooldown && !isFollowing {
                    // Show locked state visually during cooldown
                    Image(systemName: "hourglass")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                        .frame(width: 60, height: 30)
                } else {
                    // P1 FIX: Three-state label — Follow / Requested / Following
                    HStack(spacing: 4) {
                        if followState == .following || followState == .mutualFollow {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(followState.buttonTitle)
                            .font(.systemScaled(13, weight: .semibold))
                    }
                    .frame(minWidth: 72, maxWidth: 90, minHeight: 30, maxHeight: 30)
                }
            }
            .foregroundStyle(followButtonForeground)
            .padding(.horizontal, 4)
            .background { followButtonBackground }
        }
        .disabled(isInProgress || burstCoordinator.frictionState == .cooldown)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: followState)
        .animation(.easeInOut(duration: 0.2), value: burstCoordinator.frictionState)
        .accessibilityLabel(followState.buttonTitle)
        .accessibilityHint(
            followState == .requested
                ? "Tap to cancel follow request"
                : isFollowing ? "Tap to unfollow" : "Tap to follow"
        )
    }

    private var followButtonForeground: Color {
        switch followState {
        case .notFollowing, .followsYou:
            return .white
        case .requested, .following, .mutualFollow:
            return .primary
        }
    }

    @ViewBuilder
    private var followButtonBackground: some View {
        switch followState {
        case .notFollowing, .followsYou:
            if burstCoordinator.frictionState == .cooldown {
                Capsule().fill(Color.orange.opacity(0.12))
            } else {
                // P1 FIX: AMEN gold capsule per design spec
                Capsule().fill(Color.amenGold)
            }
        case .requested:
            // Gray outlined capsule — pending request
            Capsule()
                .fill(Color(.systemFill))
                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
        case .following, .mutualFollow:
            // Outlined ghost capsule — already following
            Capsule()
                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5)
        }
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

                // P1 FIX: push authoritative state to FollowStateManager (single source of truth)
                let newState: FollowStateManager.FollowState = recommendation.isPrivate ? .requested : .following
                FollowStateManager.shared.updateState(for: recommendation.id, state: newState)
                withAnimation { followState = newState }

                burstCoordinator.recordFollow(targetUserId: recommendation.id)
                if !recommendation.isPrivate { onFollowed?() }
            } catch {
                dlog("SuggestedUserRow follow failed: \(error)")
            }
            isInProgress = false
        }
    }

    // MARK: - Cancel Pending Request

    private func cancelRequest() {
        Task {
            // Optimistic revert
            withAnimation { followState = .notFollowing }
            FollowStateManager.shared.updateState(for: recommendation.id, state: .notFollowing)

            guard let currentUID = Auth.auth().currentUser?.uid else { return }
            do {
                let snap = try await Firestore.firestore()
                    .collection("followRequests")
                    .whereField("fromUserId", isEqualTo: currentUID)
                    .whereField("toUserId", isEqualTo: recommendation.id)
                    .whereField("status", isEqualTo: "pending")
                    .limit(to: 1)
                    .getDocuments()
                for doc in snap.documents { try await doc.reference.delete() }
            } catch {
                // Revert on failure
                withAnimation { followState = .requested }
                FollowStateManager.shared.updateState(for: recommendation.id, state: .requested)
                dlog("SuggestedUserRow cancel request failed: \(error)")
            }
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
