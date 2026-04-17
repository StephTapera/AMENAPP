// SuggestedAccountPeekSheet.swift
// AMENAPP
//
// Bottom sheet with progressive expand for previewing a suggested account.
// Detents: 45% (compact peek) → 90% (full detail).
// Content priority varies by surface (see plan Phase 3 table).

import SwiftUI

struct SuggestedAccountPeekSheet: View {
    @StateObject private var vm: PeekSheetViewModel
    @Environment(\.dismiss) private var dismiss

    let item: SuggestionItem
    let surface: SuggestionSurface
    let onViewFullProfile: (String) -> Void

    @State private var showUnfollowConfirm = false

    init(item: SuggestionItem, surface: SuggestionSurface, onViewFullProfile: @escaping (String) -> Void) {
        self.item = item
        self.surface = surface
        self.onViewFullProfile = onViewFullProfile
        _vm = StateObject(wrappedValue: PeekSheetViewModel(userId: item.id, surface: surface))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Identity header (all surfaces, priority 1)
                identityHeader

                // Follow button
                followSection

                // Surface-ordered content
                surfaceOrderedContent

                // View full profile button
                viewFullProfileButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .task {
            vm.prepopulate(from: item)
            await vm.load()
        }
        .confirmationDialog("Unfollow @\(vm.handle)?", isPresented: $showUnfollowConfirm, titleVisibility: .visible) {
            Button("Unfollow", role: .destructive) {
                Task { await vm.unfollow() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Identity Header

    private var identityHeader: some View {
        VStack(spacing: 10) {
            SuggestionAvatarView(item: item, size: 72)

            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Text(vm.displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)

                    if vm.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Text("@\(vm.handle)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            if vm.isPrivateAccount {
                Label("This account is private", systemImage: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(.systemFill)))
            }
        }
    }

    // MARK: - Follow Section

    private var followSection: some View {
        HStack(spacing: 10) {
            SuggestionFollowButton(
                state: vm.followState,
                isLoading: vm.isLoadingFollow,
                onFollow: {
                    HapticManager.impact(style: .medium)
                    Task { await vm.follow() }
                },
                onCancelRequest: {
                    HapticManager.impact(style: .light)
                    Task { await vm.cancelRequest() }
                },
                onUnfollow: {
                    showUnfollowConfirm = true
                }
            )
            .frame(maxWidth: 140)
        }
    }

    // MARK: - Surface-Ordered Content

    @ViewBuilder
    private var surfaceOrderedContent: some View {
        switch surface {
        case .openTable:
            openTableOrder
        case .prayer:
            prayerOrder
        case .testimonies:
            testimoniesOrder
        }
    }

    // OpenTable: Mutuals → Bio → Stats → Recent Posts → Shared Topics
    private var openTableOrder: some View {
        VStack(spacing: 14) {
            if !vm.mutualSignals.isEmpty { mutualContextSection }
            if let bio = vm.bio, !bio.isEmpty { bioSection(bio) }
            statsRow
            if !vm.recentPosts.isEmpty { recentPostsSection }
            if !vm.sharedTopics.isEmpty { sharedTopicsSection }
        }
    }

    // Prayer: Prayer Themes → Recent Posts → Mutuals → Bio → Stats → Shared Topics
    private var prayerOrder: some View {
        VStack(spacing: 14) {
            if !vm.prayerThemes.isEmpty { prayerThemesSection }
            if !vm.recentPosts.isEmpty { recentPostsSection }
            if !vm.mutualSignals.isEmpty { mutualContextSection }
            if let bio = vm.bio, !bio.isEmpty { bioSection(bio) }
            statsRow
            if !vm.sharedTopics.isEmpty { sharedTopicsSection }
        }
    }

    // Testimonies: Recent Posts → Testimony Resonance → Mutuals → Bio → Stats → Shared Topics
    private var testimoniesOrder: some View {
        VStack(spacing: 14) {
            if !vm.recentPosts.isEmpty { recentPostsSection }
            if !vm.mutualSignals.isEmpty { mutualContextSection }
            if let bio = vm.bio, !bio.isEmpty { bioSection(bio) }
            statsRow
            if !vm.sharedTopics.isEmpty { sharedTopicsSection }
        }
    }

    // MARK: - Content Sections

    private func bioSection(_ bio: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("About")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(bio)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsRow: some View {
        HStack(spacing: 24) {
            statItem(count: vm.followerCount, label: "Followers")
            statItem(count: vm.postCount, label: "Posts")
        }
        .frame(maxWidth: .infinity)
    }

    private func statItem(count: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text(formatCount(count))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var mutualContextSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mutual context")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(vm.mutualSignals.prefix(3)) { signal in
                HStack(spacing: 6) {
                    Image(systemName: signalIcon(for: signal.type))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(signalLabel(for: signal.type))
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func signalIcon(for type: ContextSignalType) -> String {
        switch type {
        case .mutualFollowers: return "person.2.fill"
        case .sharedChurch:    return "building.columns.fill"
        case .sharedInterests: return "heart.fill"
        }
    }

    private func signalLabel(for type: ContextSignalType) -> String {
        switch type {
        case .mutualFollowers(let connections, let totalCount):
            if let first = connections.first {
                if totalCount > 1 {
                    return "Followed by \(first.displayName) + \(totalCount - 1) others"
                }
                return "Followed by \(first.displayName)"
            }
            return "\(totalCount) mutual connection\(totalCount == 1 ? "" : "s")"
        case .sharedChurch(let name):
            return "Both attend \(name)"
        case .sharedInterests(let topics):
            return "Shared interests: \(topics.prefix(3).joined(separator: ", "))"
        }
    }

    private var sharedTopicsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shared interests")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            AMENFlowLayout(spacing: 6) {
                ForEach(vm.sharedTopics.prefix(6), id: \.self) { topic in
                    Text(topic)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(.systemFill)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var prayerThemesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prayer heart")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            AMENFlowLayout(spacing: 6) {
                ForEach(vm.prayerThemes.prefix(5), id: \.self) { theme in
                    Text(theme)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(.systemFill)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recentPostsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent posts")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(vm.recentPosts.prefix(2)) { preview in
                VStack(alignment: .leading, spacing: 4) {
                    Text(preview.content)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(3)

                    Text(preview.createdAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - View Full Profile Button

    private var viewFullProfileButton: some View {
        Button {
            HapticManager.impact(style: .light)
            AMENAnalyticsService.shared.track(.suggestionProfileOpen(suggestedUserId: vm.userId))
            dismiss()
            onViewFullProfile(vm.userId)
        } label: {
            Text("View full profile")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View \(vm.displayName)'s full profile")
    }

    // MARK: - Helpers

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
