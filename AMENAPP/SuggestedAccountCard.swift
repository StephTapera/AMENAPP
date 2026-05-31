// SuggestedAccountCard.swift
// AMENAPP
//
// Surface-aware suggestion card for the Suggested Accounts rail.
// Same 168×240 Liquid Glass background across all surfaces,
// with surface-specific content slots:
//   OpenTable  → bio + follower stats
//   Prayer     → prayer themes + activity
//   Testimonies → testimony excerpt + narrative reason

import SwiftUI

struct SuggestedAccountCard: View {
    let item: SuggestionItem
    let surface: SuggestionSurface
    let followState: FollowStateManager.FollowState
    let isLoadingFollow: Bool
    let onFollow: () -> Void
    let onCancelRequest: () -> Void
    let onUnfollow: () -> Void
    let onDismiss: () -> Void
    let onOpenProfile: () -> Void
    let onView: () -> Void

    @State private var showUnfollowConfirm = false

    private let cardWidth: CGFloat = 168
    private let cardHeight: CGFloat = 240

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardBody
            dismissPill
        }
        .frame(width: cardWidth)
        .confirmationDialog("Unfollow @\(item.handle)?", isPresented: $showUnfollowConfirm, titleVisibility: .visible) {
            Button("Unfollow", role: .destructive) { onUnfollow() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Card Body

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: Avatar + identity
            identitySection
                .padding(.horizontal, 12)
                .padding(.top, 14)

            // Surface-specific content
            surfaceContent
                .padding(.horizontal, 12)
                .padding(.top, 6)

            // Mutual context row (all surfaces)
            if item.mutualCount > 0 || item.contextLine != nil {
                mutualContextRow
                    .padding(.horizontal, 12)
                    .padding(.top, 5)
            }

            Spacer(minLength: 0)

            // Action buttons
            actionButtons
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background { glassBackground }
        // HIGH FIX: .contain keeps child buttons (Follow, View, Dismiss) individually
        // reachable by VoiceOver and Switch Control, while the card still has a
        // descriptive group label for context.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.displayName), @\(item.handle). \(item.reasonText)")
        // HIGH FIX: Custom action so VoiceOver users can open the peek sheet
        // without needing a long-press gesture (which is inaccessible to VoiceOver/Switch Control).
        .accessibilityAction(named: "View profile") { onView() }
    }

    // MARK: - Identity Section

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: onOpenProfile) {
                SuggestionAvatarView(item: item, size: 48)
            }
            .buttonStyle(.plain)

            HStack(spacing: 3) {
                Text(item.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if item.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                }
            }

            Text("@\(item.handle)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Surface-Specific Content

    @ViewBuilder
    private var surfaceContent: some View {
        switch surface {
        case .openTable:
            openTableContent
        case .prayer:
            prayerContent
        case .testimonies:
            testimoniesContent
        }
    }

    // OpenTable: bio + follower stats
    private var openTableContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let bio = item.bio, !bio.isEmpty {
                Text(bio)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(item.reasonText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if item.followerCount > 0 {
                Text("\(formatCount(item.followerCount)) followers")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if let badge = item.accountType.badge {
                accountTypeBadge(badge)
            }
        }
    }

    // Prayer: prayer themes + activity
    private var prayerContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !item.prayerThemes.isEmpty {
                Text(item.prayerThemes.prefix(2).joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.9))
                    .lineLimit(1)
            }

            Text(item.reasonText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.8))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let badge = item.accountType.badge {
                accountTypeBadge(badge)
            }
        }
    }

    // Testimonies: testimony excerpt + narrative reason
    private var testimoniesContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let excerpt = item.recentTestimonyExcerpt, !excerpt.isEmpty {
                Text("\u{201C}\(excerpt)\u{201D}")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .italic()
            }

            Text(item.reasonText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.8))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let badge = item.accountType.badge {
                accountTypeBadge(badge)
            }
        }
    }

    private func accountTypeBadge(_ badge: String) -> some View {
        Text(badge)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color(.systemFill)))
            .padding(.top, 2)
    }

    // MARK: - Mutual Context Row

    private var mutualContextRow: some View {
        HStack(spacing: 4) {
            if !item.mutualAvatarURLs.isEmpty {
                mutualAvatarStack
            }

            if let context = item.contextLine {
                Text(context)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else if item.mutualCount > 0 {
                Text("Mutuals · community")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var mutualAvatarStack: some View {
        HStack(spacing: -6) {
            ForEach(Array(item.mutualAvatarURLs.prefix(3).enumerated()), id: \.offset) { index, urlString in
                CachedAsyncImage(url: URL(string: urlString)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color(.systemGray5))
                }
                .frame(width: 16, height: 16)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 1))
                .zIndex(Double(3 - index))
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 6) {
            SuggestionFollowButton(
                state: followState,
                isLoading: isLoadingFollow,
                onFollow: onFollow,
                onCancelRequest: onCancelRequest,
                onUnfollow: { showUnfollowConfirm = true }
            )

            Button(action: onView) {
                Text("View")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.55))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
                            )
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(item.displayName)'s profile")
        }
    }

    // MARK: - Dismiss Pill (Glass micro pill)

    private var dismissPill: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary.opacity(0.45))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .padding(8)
        .accessibilityLabel("Dismiss \(item.displayName)")
    }

    // MARK: - Glass Background

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.45), Color.clear],
                            startPoint: .top,
                            endPoint: .init(x: 0.5, y: 0.3)
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.70), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
            .shadow(color: .black.opacity(0.02), radius: 2, x: 0, y: 1)
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
