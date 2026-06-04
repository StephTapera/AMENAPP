// AmenHubSectionView.swift
// Amen Hub — Unified Inbox Section (Agent B, Spiritual OS)
//
// Placement: inserted at the TOP of MessagesView, above DM threads.
// This view is PURELY ADDITIVE — it never removes or replaces DM content.
//
// Feature flag: spiritualOS_hub_enabled (Remote Config / AppStorage)
//   false  → EmptyView(), zero layout impact on MessagesView
//   true   → renders the full Hub section
//
// Design rules enforced here:
//   • No FOMO language ("🔥 3 unread!"). Unread count is calm and informational.
//   • No engagement-bait copy. Neutral, faith-native language only.
//   • No glass-on-glass layering (GlassCard rows sit on an amenCream background).

import SwiftUI
import Firebase
import FirebaseFunctions
import Foundation

// MARK: - AmenHubSectionView

struct AmenHubSectionView: View {

    @ObservedObject var viewModel: AmenHubViewModel
    var userId: String

    // MARK: Feature flag
    @AppStorage("spiritualOS_hub_enabled") private var isEnabled = false

    // MARK: Navigation
    @State private var showFullHub = false

    var body: some View {
        if isEnabled {
            hubContent
        }
        // else: EmptyView() — no layout space consumed
    }

    // MARK: - Full Hub Section

    private var hubContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            filterChipRail
            itemsList
        }
        .task {
            await viewModel.load(userId: userId)
        }
        .sheet(isPresented: $showFullHub) {
            // Full-screen Hub sheet — wired to the same viewModel so state is shared.
            AmenHubFullSheetView(viewModel: viewModel, userId: userId)
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("Amen Hub")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.amenBlack)
                .accessibilityAddTraits(.isHeader)

            let unread = viewModel.unreadCount
            if unread > 0 {
                GlassChip(
                    label: "\(unread) unread",
                    tint: .amenGold,
                    size: .compact,
                    isActive: true
                )
                .accessibilityLabel("\(unread) unread items")
            }

            Spacer()

            Button {
                showFullHub = true
            } label: {
                Text("See all")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.amenGoldText)
            }
            .accessibilityLabel("See all hub items")
            .accessibilityHint("Opens the full Amen Hub inbox")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Filter Chip Rail

    private var filterChipRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip
                GlassChip(
                    label: "All",
                    tint: .amenSlate,
                    size: .compact,
                    isActive: viewModel.filterType == nil
                ) {
                    viewModel.setFilter(nil)
                }
                .accessibilityLabel("Show all hub items")
                .accessibilityAddTraits(viewModel.filterType == nil ? [.isSelected] : [])

                // Faith-native filter chips — only the surfaced subset per design.
                ForEach(HubFilterOption.allCases) { option in
                    GlassChip(
                        label: option.label,
                        tint: option.tint,
                        size: .compact,
                        isActive: viewModel.filterType == option.itemType
                    ) {
                        viewModel.setFilter(option.itemType)
                    }
                    .accessibilityLabel("Filter by \(option.label)")
                    .accessibilityAddTraits(viewModel.filterType == option.itemType ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.bottom, 10)
    }

    // MARK: - Items List

    @ViewBuilder
    private var itemsList: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            loadingPlaceholders
        } else if viewModel.items.isEmpty {
            emptyState
        } else {
            VStack(spacing: 8) {
                ForEach(viewModel.items.prefix(5)) { item in
                    HubItemRow(
                        item: item,
                        onMarkRead: { viewModel.markRead(itemId: item.id, userId: userId) },
                        onPin: {
                            Task { await viewModel.pin(itemId: item.id, userId: userId) }
                        }
                    )
                    .padding(.horizontal, 16)
                }

                if viewModel.hasMore {
                    GlassChip(
                        label: "Show more in Hub",
                        icon: "chevron.down",
                        tint: .amenSlate,
                        size: .regular,
                        isActive: false
                    ) {
                        Task { await viewModel.loadMore(userId: userId) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .accessibilityLabel("Load more hub items")
                    .accessibilityHint("Fetches the next page of inbox items")
                }
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: - Loading Placeholders (3 rows at reduced opacity)

    private var loadingPlaceholders: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                HubItemPlaceholderRow()
                    .padding(.horizontal, 16)
            }
        }
        .opacity(0.3)
        .padding(.bottom, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Text("You're all caught up")
            .font(.subheadline)
            .foregroundStyle(Color.amenSlate)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
            .accessibilityLabel("Inbox is empty — you're all caught up")
    }
}

// MARK: - HubItemRow

private struct HubItemRow: View {

    let item: HubItem
    let onMarkRead: () -> Void
    let onPin: () -> Void

    var body: some View {
        GlassCard(tint: tagTint(for: item.tag)) {
            HStack(alignment: .top, spacing: 12) {
                avatarView
                centerContent
                trailingColumn
            }
            .padding(12)
        }
        .opacity(item.isRead ? 0.8 : 1.0)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                onMarkRead()
            } label: {
                Label("Mark Read", systemImage: "checkmark")
            }
            .tint(Color.amenSlate)
            .accessibilityLabel("Mark \(item.title) as read")

            Button {
                onPin()
            } label: {
                Label("Pin", systemImage: "pin.fill")
            }
            .tint(Color.amenGold)
            .accessibilityLabel(item.isPinned ? "Unpin \(item.title)" : "Pin \(item.title)")
        }
    }

    // MARK: Avatar

    @ViewBuilder
    private var avatarView: some View {
        if let avatarString = item.senderAvatar,
           let url = URL(string: avatarString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                case .failure, .empty:
                    fallbackAvatarCircle
                @unknown default:
                    fallbackAvatarCircle
                }
            }
            .frame(width: 40, height: 40)
            .accessibilityLabel(item.senderName.map { "\($0)'s avatar" } ?? "Sender avatar")
            .accessibilityHidden(true) // decorative; sender name in centerContent is sufficient
        } else {
            fallbackAvatarCircle
        }
    }

    private var fallbackAvatarCircle: some View {
        ZStack {
            Circle()
                .fill(tagTint(for: item.tag).opacity(0.18))
                .frame(width: 40, height: 40)
            Image(systemName: item.type.fallbackIcon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tagTint(for: item.tag))
        }
        .accessibilityHidden(true)
    }

    // MARK: Center

    private var centerContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let name = item.senderName {
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.amenBlack)
                    .lineLimit(1)
            } else {
                Text(item.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.amenBlack)
                    .lineLimit(1)
            }

            if let preview = item.preview {
                Text(preview)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.amenSlate)
                    .lineLimit(2)
            }

            GlassChip(
                label: item.tag,
                tint: tagTint(for: item.tag),
                size: .compact,
                isActive: true
            )
            .accessibilityLabel("Tag: \(item.tag)")
        }
    }

    // MARK: Trailing

    private var trailingColumn: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(relativeTimestamp(for: item.createdAt))
                .font(.system(size: 12))
                .foregroundStyle(Color.amenSlate.opacity(0.7))
                .accessibilityLabel("Received \(relativeTimestamp(for: item.createdAt))")

            Button(action: onPin) {
                Image(systemName: item.isPinned ? "heart.fill" : "heart")
                    .font(.system(size: 16))
                    .foregroundStyle(item.isPinned ? Color.amenGold : Color.amenSlate.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isPinned ? "Unpin this item" : "Pin this item")
            .accessibilityHint(item.isPinned ? "Removes the pin from this item" : "Pins this item so it stays at the top")

            if !item.isRead {
                Circle()
                    .fill(Color.amenGold)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Unread")
            }
        }
    }

    // MARK: Tag tint

    private func tagTint(for tag: String) -> Color {
        let lower = tag.lowercased()
        if lower.contains("prayer") { return .amenBlue }
        if lower.contains("berean") { return .amenPurple }
        if lower.contains("testimony") || lower.contains("church") ||
           lower.contains("community") || lower.contains("event") ||
           lower.contains("mentor") { return .amenGold }
        return .amenSlate
    }

    // MARK: Relative timestamp

    private func relativeTimestamp(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

// MARK: - HubItemPlaceholderRow

private struct HubItemPlaceholderRow: View {
    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(Color.amenSlate.opacity(0.25))
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.amenSlate.opacity(0.25))
                        .frame(width: 100, height: 12)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.amenSlate.opacity(0.15))
                        .frame(width: 200, height: 10)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.amenSlate.opacity(0.15))
                        .frame(width: 160, height: 10)
                }

                Spacer()
            }
            .padding(12)
        }
        .accessibilityLabel("Loading hub item")
        .accessibilityHidden(true)
    }
}

// MARK: - HubFilterOption
// Defines the subset of HubItemType exposed in the filter chip rail.
// Intentionally does NOT expose every HubItemType — keep the rail scannable.
// Maps to HubItemType cases; each option must have a unique itemType so filtering is unambiguous.

private enum HubFilterOption: CaseIterable, Identifiable {
    case prayer
    case church
    case events
    case testimony

    var id: String { label }

    var label: String {
        switch self {
        case .prayer:    return "Prayer"
        case .church:    return "Church"
        case .events:    return "Events"
        case .testimony: return "Testimony"
        }
    }

    var itemType: HubItemType {
        switch self {
        case .prayer:    return .prayerRequest
        case .church:    return .churchNoteMention
        case .events:    return .eventInvite
        case .testimony: return .testimony
        }
    }

    var tint: Color {
        switch self {
        case .prayer:    return .amenBlue
        case .church:    return .amenGold
        case .events:    return .amenGold
        case .testimony: return .amenGold
        }
    }
}

// MARK: - AmenHubFullSheetView
// Minimal full-screen sheet presented by "See all".
// Reuses the same viewModel — no re-fetch on open.

struct AmenHubFullSheetView: View {

    @ObservedObject var viewModel: AmenHubViewModel
    var userId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GlassSheet(title: "Amen Hub", onDismiss: { dismiss() }) {
            ScrollView {
                VStack(spacing: 8) {
                    if viewModel.isLoading && viewModel.items.isEmpty {
                        ForEach(0..<5, id: \.self) { _ in
                            HubItemPlaceholderRow()
                                .padding(.horizontal, 16)
                                .opacity(0.3)
                        }
                    } else if viewModel.items.isEmpty {
                        Text("You're all caught up")
                            .font(.subheadline)
                            .foregroundStyle(Color.amenSlate)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    } else {
                        ForEach(viewModel.items) { item in
                            HubItemRow(
                                item: item,
                                onMarkRead: {
                                    viewModel.markRead(itemId: item.id, userId: userId)
                                },
                                onPin: {
                                    Task { await viewModel.pin(itemId: item.id, userId: userId) }
                                }
                            )
                            .padding(.horizontal, 16)
                        }

                        if viewModel.hasMore {
                            GlassChip(
                                label: "Load more",
                                icon: "chevron.down",
                                tint: .amenSlate,
                                size: .regular
                            ) {
                                Task { await viewModel.loadMore(userId: userId) }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .accessibilityLabel("Load more hub items")
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
    }
}

