// SpacesNavigationView.swift
// AMENAPP — Spaces v2 Navigation Shell (Agent C)
//
// Top-level community Spaces list — Slack-style sidebar adapted for iOS.
// Shows all non-deleted Spaces for a given communityId, with filter tabs and
// type-driven row icons. Gated Spaces check EntitlementService before navigating.

import SwiftUI
import FirebaseAuth

@MainActor
struct SpacesNavigationView: View {

    let communityId: String

    @StateObject private var viewModel = SpacesShellViewModel()

    // Locked space: shown as LockedPreviewShell sheet
    @State private var lockedSpaceForPreview: AmenSpaceExtended? = nil
    // Navigation target: shown in NavigationLink push
    @State private var navigationTarget: AmenSpaceExtended? = nil

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    filterTabs
                    spacesList
                }

                // FAB — Space creation wizard entry (Agent D wires destination)
                fabButton
            }
            .navigationTitle("Spaces")
            .navigationBarTitleDisplayMode(.large)
            .task { await viewModel.loadSpaces(communityId: communityId) }
            .sheet(item: $lockedSpaceForPreview) { space in
                // LockedPreviewShell shown when user lacks entitlement.
                // Agent E wires onUnlock to its purchase sheet;
                // for now we dismiss and log.
                LockedPreviewShell(space: space) {
                    // TODO(Agent E): Replace with purchaseSheet presentation.
                    lockedSpaceForPreview = nil
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Filter tabs

    private var filterTabs: some View {
        AmenLiquidGlassControlDock(placement: .top) {
            ForEach(SpaceListFilter.allCases) { filter in
                Button {
                    viewModel.applyFilter(filter)
                } label: {
                    Text(filter.rawValue)
                        .font(.subheadline.weight(viewModel.currentFilter == filter ? .semibold : .regular))
                        .foregroundStyle(
                            viewModel.currentFilter == filter
                                ? AmenTheme.Colors.textPrimary
                                : AmenTheme.Colors.textSecondary
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background {
                    if viewModel.currentFilter == filter {
                        Capsule(style: .continuous)
                            .fill(AmenTheme.Colors.selectedFill)
                    }
                }
                .accessibilityLabel(filter.accessibilityLabel)
                .accessibilityAddTraits(viewModel.currentFilter == filter ? .isSelected : [])
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Spaces list

    @ViewBuilder
    private var spacesList: some View {
        if viewModel.isLoading && viewModel.spaces.isEmpty {
            Spacer()
            ProgressView()
                .accessibilityLabel("Loading Spaces")
            Spacer()
        } else if !viewModel.isLoading && viewModel.filteredSpaces.isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.largeTitle)
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .accessibilityElement(children: .combine)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.filteredSpaces) { space in
                        SpaceListRow(
                            space: space,
                            unreadCount: viewModel.unreadCounts[space.id ?? ""] ?? 0,
                            isVip: viewModel.vipSpaceIds.contains(space.id ?? "")
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { await handleSpaceTap(space) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                // Reserve space so FAB doesn't cover last row
                .padding(.bottom, 72)
            }
        }
    }

    private var emptyMessage: String {
        switch viewModel.currentFilter {
        case .all:      return "No Spaces yet. Create one with the + button."
        case .vip:      return "No VIP Spaces. Long-press a Space to mark it VIP."
        case .unreads:  return "All caught up."
        case .external: return "No shared Spaces."
        }
    }

    // MARK: - FAB

    private var fabButton: some View {
        NavigationLink {
            // TODO(Agent D): Replace EmptyView with Space creation wizard entry.
            EmptyView()
        } label: {
            ZStack {
                Circle()
                    .fill(AmenTheme.Colors.amenGold)
                    .frame(width: 56, height: 56)
                    .shadow(color: AmenTheme.Colors.amenGold.opacity(0.40), radius: 12, x: 0, y: 6)
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.black)
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 24)
        .accessibilityLabel("Create Space")
        .accessibilityHint("Opens the Space creation wizard.")
    }

    // MARK: - Tap handler

    private func handleSpaceTap(_ space: AmenSpaceExtended) async {
        guard space.accessPolicy != .free else {
            navigationTarget = space
            return
        }
        guard let userId = Auth.auth().currentUser?.uid else { return }
        guard let spaceId = space.id else { return }
        do {
            let entitlement = try await EntitlementService.shared.fetchEntitlement(
                userId: userId,
                spaceId: spaceId
            )
            let isAccessible = entitlement.map {
                $0.status == .active || $0.status == .grace
            } ?? false

            if isAccessible {
                navigationTarget = space
            } else {
                lockedSpaceForPreview = space
            }
        } catch {
            // On error, fall through to locked state for safety
            lockedSpaceForPreview = space
        }
    }
}

// MARK: - SpaceListRow

private struct SpaceListRow: View {
    let space: AmenSpaceExtended
    let unreadCount: Int
    let isVip: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 12) {
            // Type glyph icon
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(
                            reduceTransparency
                                ? AmenTheme.Colors.surfaceChip
                                : LiquidGlassTokens.blurThin
                        )
                        .frame(width: 44, height: 44)
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                        }
                    Image(systemName: typeSystemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.amenPurple)
                }

                // Lock overlay for gated Spaces
                if space.accessPolicy != .free {
                    ZStack {
                        Circle()
                            .fill(AmenTheme.Colors.amenGold)
                            .frame(width: 18, height: 18)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black)
                    }
                    .offset(x: 4, y: 4)
                }
            }
            .accessibilityHidden(true)

            // Title and description
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(space.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(1)

                    if isVip {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(AmenTheme.Colors.amenGold)
                    }
                }

                if let desc = space.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // LinkedGlyph if Space is shared with other communities
            if !space.sharedWith.isEmpty {
                LinkedGlyph(size: .small)
            }

            // Unread badge
            if unreadCount > 0 {
                Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(AmenTheme.Colors.amenPurple)
                    .clipShape(Capsule(style: .continuous))
                    .accessibilityLabel("\(unreadCount) unread")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceCard)
            } else {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(LiquidGlassTokens.blurThin)
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityHint("Double-tap to open this Space.")
    }

    private var typeSystemImage: String {
        switch space.type {
        case .chat:         return "number"
        case .bibleStudy:   return "book.closed.fill"
        case .group:        return "person.3.fill"
        case .announcement: return "megaphone.fill"
        }
    }

    private var rowAccessibilityLabel: String {
        var parts = [space.title, space.type.displayName]
        if space.accessPolicy != .free { parts.append("Locked") }
        if !space.sharedWith.isEmpty   { parts.append("Shared with other communities") }
        if unreadCount > 0             { parts.append("\(unreadCount) unread") }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("SpacesNavigationView") {
    SpacesNavigationView(communityId: "preview_community")
}
#endif
