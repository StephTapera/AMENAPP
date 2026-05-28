// SpacesListView.swift
// AMENAPP — Spaces v2 Navigation Shell (Agent C)
//
// Slack-style channel list for a selected community.
// Filter pill row: All | VIP | Unreads | External.
// Each Space tile: SpaceAvatarView + title + type badge + unread dot + preview.
// Shared Spaces: LinkedCommunityGlyph on the tile.
// Paid Spaces without entitlement: gold lock icon.
// Pull-to-refresh + Firestore real-time listener.
// "Start something" FAB → Agent D's creation wizard (placeholder until D wires).

import SwiftUI
import FirebaseAuth

// MARK: - Placeholder views for downstream agents

/// Placeholder content shown until Agent D wires the Space creation wizard.
struct SpaceCreationWizardPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(AmenTheme.Colors.amenGold)
            Text("Creation wizard coming soon")
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AmenTheme.Colors.backgroundPrimary)
    }
}

/// Placeholder chat view shown until Agent B wires SpacesChatView.
struct SpacesChatViewPlaceholder: View {
    var body: some View {
        Text("Chat coming soon")
            .font(.body)
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Placeholder lock view shown until Agent E wires SpaceLockedView.
struct SpaceLockedPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(AmenTheme.Colors.amenGold)
            Text("Locked")
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - AmenSpaceExtended Hashable conformance (needed for navigationDestination(item:))

extension AmenSpaceExtended: Hashable {
    public static func == (lhs: AmenSpaceExtended, rhs: AmenSpaceExtended) -> Bool {
        lhs.id == rhs.id
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - SpacesListView

@MainActor
struct SpacesListView: View {

    let communityId: String

    /// Called when user taps the "Start something" FAB.
    /// Agent D replaces EmptyView with the creation wizard entry point.
    var onStartSomething: (() -> Void)? = nil

    @StateObject private var viewModel = SpacesShellViewModel()

    @State private var navigationTarget: AmenSpaceExtended? = nil
    @State private var lockedSpaceTarget: AmenSpaceExtended? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                filterPillRow
                spacesList
            }

            fabButton
        }
        .navigationTitle("Spaces")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $navigationTarget) { space in
            SpaceDetailView(space: space, communityId: communityId)
        }
        .task { await viewModel.loadSpaces(communityId: communityId) }
        .refreshable { await viewModel.loadSpaces(communityId: communityId) }
        .sheet(item: $lockedSpaceTarget) { space in
            LockedPreviewShell(space: space) {
                // TODO(Agent E): Replace with purchase sheet presentation.
                lockedSpaceTarget = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Filter pill row

    private var filterPillRow: some View {
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
            loadingView
        } else if !viewModel.isLoading && viewModel.filteredSpaces.isEmpty {
            emptyStateView
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    // "Continue Studying" rail — surfaces bible study Spaces at the top
                    let studySpaces = viewModel.spaces.filter { $0.type == .bibleStudy }
                    if !studySpaces.isEmpty {
                        SpaceRailView(title: "Continue Studying", items: studySpaces) { space in
                            AMENGlassCard(
                                width: 160,
                                height: 100,
                                tintColor: AmenTheme.Colors.amenGold
                            ) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Image(systemName: "book.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AmenTheme.Colors.amenGold)
                                    Text(space.title)
                                        .font(.caption.bold())
                                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                                        .lineLimit(2)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                            .onTapGesture {
                                Task { await handleTap(space) }
                            }
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    }

                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.filteredSpaces) { space in
                            SpaceListTile(
                                space: space,
                                unreadCount: viewModel.unreadCounts[space.id ?? ""] ?? 0,
                                isVip: viewModel.vipSpaceIds.contains(space.id ?? "")
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Task { await handleTap(space) }
                            }
                            .contextMenu {
                                Button {
                                    viewModel.toggleVip(spaceId: space.id ?? "")
                                } label: {
                                    let isVip = viewModel.vipSpaceIds.contains(space.id ?? "")
                                    Label(isVip ? "Remove from VIP" : "Mark as VIP",
                                          systemImage: isVip ? "star.slash" : "star")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.bottom, 80) // clear FAB
                }
            }
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .accessibilityLabel("Loading Spaces")
            Spacer()
        }
    }

    private var emptyStateView: some View {
        VStack {
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
        }
    }

    private var emptyMessage: String {
        switch viewModel.currentFilter {
        case .all:      return "No Spaces yet. Tap + to start something."
        case .vip:      return "No VIP Spaces. Long-press a Space to mark it VIP."
        case .unreads:  return "All caught up."
        case .external: return "No shared Spaces."
        }
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button {
            onStartSomething?()
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
        .accessibilityLabel("Start something")
        .accessibilityHint("Opens the Space creation wizard.")
    }

    // MARK: - Tap handler

    private func handleTap(_ space: AmenSpaceExtended) async {
        if space.accessPolicy == .free {
            navigationTarget = space
            return
        }
        guard let userId = Auth.auth().currentUser?.uid,
              let spaceId = space.id else { return }
        do {
            let entitlement = try await EntitlementService.shared.fetchEntitlement(
                userId: userId,
                spaceId: spaceId
            )
            let accessible: Bool
            if let e = entitlement {
                accessible = e.status == .active || e.status == .grace
            } else {
                accessible = false
            }
            let isAccessible = accessible
            if isAccessible {
                navigationTarget = space
            } else {
                lockedSpaceTarget = space
            }
        } catch {
            // On error, treat as locked for safety.
            lockedSpaceTarget = space
        }
    }
}

// MARK: - SpaceListTile

struct SpaceListTile: View {
    let space: AmenSpaceExtended
    let unreadCount: Int
    let isVip: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 12) {
            // Avatar with optional shared badge
            SpaceAvatarView(
                avatarURL: space.avatarURL,
                title: space.title,
                size: 44,
                isShared: !space.sharedWith.isEmpty,
                sharedCommunityName: space.sharedWith.first.map { "community \($0)" } ?? ""
            )
            .overlay(alignment: .bottomTrailing) {
                // Lock overlay for paid Spaces
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
                    .accessibilityHidden(true)
                }
            }

            // Title and type
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: space.type.systemImageName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AmenTheme.Colors.amenPurple)
                        .accessibilityHidden(true)

                    Text(space.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(1)

                    if isVip {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(AmenTheme.Colors.amenGold)
                            .accessibilityHidden(true)
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

            // Linked glyph for shared Spaces
            if !space.sharedWith.isEmpty {
                LinkedGlyph(size: .small)
                    .accessibilityHidden(true)
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
        .accessibilityLabel(tileAccessibilityLabel)
        .accessibilityHint("Double-tap to open this Space.")
    }

    private var tileAccessibilityLabel: String {
        var parts = [space.title, space.type.displayName]
        if space.accessPolicy != .free { parts.append("Locked") }
        if !space.sharedWith.isEmpty { parts.append("Shared with other communities") }
        if unreadCount > 0 { parts.append("\(unreadCount) unread") }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("SpacesListView") {
    NavigationStack {
        SpacesListView(communityId: "preview_community")
    }
}
#endif
