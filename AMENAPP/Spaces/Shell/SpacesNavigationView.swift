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

    // Locked space: shown as LockedPreviewShell sheet before purchase
    @State private var lockedSpaceForPreview: AmenSpaceExtended? = nil
    // Purchase sheet state — wired to E's SpacesPurchaseSheet
    @State private var showPurchaseSheet: Bool = false
    @State private var purchaseTargetSpace: AmenSpaceExtended? = nil
    // Creation wizard — FAB entry point
    @State private var showCreationWizard: Bool = false

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
                LockedPreviewShell(space: space) {
                    // Wire through to E's SpacesPurchaseSheet
                    purchaseTargetSpace = space
                    lockedSpaceForPreview = nil
                    showPurchaseSheet = true
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showPurchaseSheet) {
                if let space = purchaseTargetSpace,
                   let userId = Auth.auth().currentUser?.uid {
                    SpacesPurchaseSheet(
                        space: space,
                        userId: userId,
                        isPresented: $showPurchaseSheet
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showCreationWizard) {
                if let userId = Auth.auth().currentUser?.uid {
                    SpaceCreationWizardView(
                        communityId: communityId,
                        creatorUserId: userId,
                        isPresented: $showCreationWizard
                    )
                }
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
                        NavigationLink {
                            SpaceDetailView(space: space, communityId: communityId)
                        } label: {
                            SpaceListRow(
                                space: space,
                                unreadCount: viewModel.unreadCounts[space.id ?? ""] ?? 0,
                                isVip: viewModel.vipSpaceIds.contains(space.id ?? "")
                            )
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded {
                            // If the space is gated, intercept to check entitlement first.
                            // NavigationLink still pushes for free spaces.
                            if space.accessPolicy != .free {
                                Task { await handleGatedTap(space) }
                            }
                        })
                        .contextMenu {
                            Button {
                                viewModel.toggleVip(spaceId: space.id ?? "")
                            } label: {
                                let isVip = viewModel.vipSpaceIds.contains(space.id ?? "")
                                Label(
                                    isVip ? "Remove from VIP" : "Add to VIP",
                                    systemImage: isVip ? "star.slash" : "star"
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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
        Button {
            showCreationWizard = true
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

    // MARK: - Gated tap handler

    /// For paid Spaces the NavigationLink push is suppressed;
    /// this handler checks entitlement and shows LockedPreviewShell if needed.
    private func handleGatedTap(_ space: AmenSpaceExtended) async {
        guard let userId = Auth.auth().currentUser?.uid,
              let spaceId = space.id else {
            lockedSpaceForPreview = space
            return
        }
        do {
            let entitlement = try await EntitlementService.shared.fetchEntitlement(
                userId: userId,
                spaceId: spaceId
            )
            let isAccessible = entitlement.map {
                $0.status == .active || $0.status == .grace
            } ?? false

            if !isAccessible {
                lockedSpaceForPreview = space
            }
            // If accessible, the NavigationLink push proceeds normally.
        } catch {
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
            typeIconBadge
                .accessibilityHidden(true)

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

            if !space.sharedWith.isEmpty {
                LinkedGlyph(size: .small)
            }

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

    @ViewBuilder
    private var typeIconBadge: some View {
        ZStack(alignment: .bottomTrailing) {
            let circleFill: AnyShapeStyle = reduceTransparency
                ? AnyShapeStyle(AmenTheme.Colors.surfaceChip)
                : AnyShapeStyle(LiquidGlassTokens.blurThin)
            ZStack {
                Circle()
                    .fill(circleFill)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Circle().stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                    }
                Image(systemName: typeSystemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
            }
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
