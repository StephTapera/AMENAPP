// ThreadListView.swift
// AMENAPP — Spaces v2 Chat Layer (Agent B)
//
// Thread list for chat and group Spaces.
// Drives All / VIP / Unreads / External filter tabs via AmenLiquidGlassControlDock.
// Agent C's LinkedGlyph and SharedCommunityBanner plug in as v2 replacements
// for the external-member placeholder glyph rendered here.

import SwiftUI
import FirebaseAuth

// MARK: - ThreadListView

struct ThreadListView: View {

    let spaceId: String
    let space: AmenSpaceExtended

    @StateObject private var service = SpacesChatService()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if space.isDeleted {
                deletedSpacePlaceholder
            } else {
                mainContent
            }
        }
        .navigationTitle(space.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await service.loadThreads(spaceId: spaceId, filter: service.currentFilter) }
        }
        .onDisappear {
            service.stopListening()
        }
    }

    // MARK: Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            filterTabBar
            threadList
        }
    }

    // MARK: Filter tab bar

    private var filterTabBar: some View {
        AmenLiquidGlassControlDock(placement: .top) {
            ForEach(ThreadFilter.allCases) { filter in
                filterPill(filter)
            }
        }
        .accessibilityLabel("Filter threads")
    }

    @ViewBuilder
    private func filterPill(_ filter: ThreadFilter) -> some View {
        let isSelected = service.currentFilter == filter
        let tabData = SpaceFilterTabData.makeAll(
            threads: service.threads,
            vipThreadIds: service.vipThreadIds,
            currentFilter: service.currentFilter
        ).first(where: { $0.filter == filter })
        let badgeCount = tabData?.count ?? 0

        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.14) : Motion.liquidSpring) {
                service.setFilter(filter)
            }
        } label: {
            HStack(spacing: 4) {
                Text(filter.displayName)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AmenTheme.Colors.amenGold : .primary)

                if badgeCount > 0 && filter != .all {
                    Text("\(badgeCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AmenTheme.Colors.amenGold, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(LiquidGlassTokens.blurThin)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.42), lineWidth: 0.5)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Thread list

    @ViewBuilder
    private var threadList: some View {
        if service.threads.isEmpty {
            emptyState(for: service.currentFilter)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(service.threads) { thread in
                        NavigationLink(
                            destination: ThreadDetailView(
                                threadId: thread.id,
                                spaceId: spaceId,
                                space: space
                            )
                        ) {
                            ThreadRowCard(thread: thread)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Empty states

    @ViewBuilder
    private func emptyState(for filter: ThreadFilter) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: emptyStateIcon(for: filter))
                .font(.system(size: 38))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text(emptyStateLabel(for: filter))
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(emptyStateLabel(for: filter))
    }

    private func emptyStateIcon(for filter: ThreadFilter) -> String {
        switch filter {
        case .all:      return "bubble.left.and.bubble.right"
        case .vip:      return "star"
        case .unreads:  return "checkmark.circle"
        case .external: return "link"
        }
    }

    private func emptyStateLabel(for filter: ThreadFilter) -> String {
        switch filter {
        case .all:      return "No threads yet. Start the conversation."
        case .vip:      return "No VIP threads. Star a thread to add it here."
        case .unreads:  return "You're all caught up."
        case .external: return "No threads with external members."
        }
    }

    // MARK: Deleted space placeholder

    private var deletedSpacePlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "xmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("This Space is no longer available.")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This Space is no longer available.")
    }
}

// MARK: - ThreadRowCard

/// Glass card for one thread row. Shows title, last-message preview,
/// unread badge, and external-member indicator.
private struct ThreadRowCard: View {

    let thread: ThreadSummary

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left column: external indicator (placeholder for C's LinkedGlyph)
            if thread.hasExternalMembers {
                externalGlyph
            }

            // Content column
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(thread.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(thread.lastMessageAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }

                if let preview = thread.lastMessagePreview {
                    Text(preview)
                        .font(.footnote)
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                        .lineLimit(2)
                }
            }

            // Unread badge
            if thread.unreadCount > 0 {
                unreadBadge(count: thread.unreadCount)
            }
        }
        .padding(14)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .fill(Color(.systemBackground))
            } else {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .fill(LiquidGlassTokens.blurThin)
                    .overlay(
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
        )
        .shadow(
            color: LiquidGlassTokens.shadowSoft.color,
            radius: LiquidGlassTokens.shadowSoft.radius,
            y: LiquidGlassTokens.shadowSoft.y
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    // MARK: Sub-components

    /// Placeholder external-member glyph (amenPurple chain icon).
    /// Agent C's `LinkedGlyph` component replaces this in v2.
    private var externalGlyph: some View {
        Image(systemName: "link")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AmenTheme.Colors.amenPurple)
            .accessibilityLabel("Has external members")
    }

    private func unreadBadge(count: Int) -> some View {
        Text("\(min(count, 99))\(count > 99 ? "+" : "")")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(AmenTheme.Colors.amenGold, in: Capsule())
            .accessibilityLabel("\(count) unread")
    }

    private var rowAccessibilityLabel: String {
        var parts: [String] = [thread.title]
        if let preview = thread.lastMessagePreview { parts.append(preview) }
        if thread.unreadCount > 0 { parts.append("\(thread.unreadCount) unread") }
        if thread.hasExternalMembers { parts.append("Has external members") }
        return parts.joined(separator: ", ")
    }
}
