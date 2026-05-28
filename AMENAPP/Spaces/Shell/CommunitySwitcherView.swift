// CommunitySwitcherView.swift
// AMENAPP — Spaces v2 Navigation Shell (Agent C)
//
// Vertical column of community avatar circles for iPhone sidebar or iPad left column.
// Active community: amenPurple ring. Long-press: community name tooltip.
// Bottom: "+" → CommunityCreateSheet.
// Notification badge overlay for communities with unread activity.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - CommunitySwitcherView

@MainActor
struct CommunitySwitcherView: View {

    // MARK: - Bindings / callbacks

    @Binding var selectedCommunityId: String
    var communities: [SpacesCommunity]
    var unreadByCommunity: [String: Int]

    // MARK: - Internal state

    @State private var showCreateSheet: Bool = false
    @State private var tooltipCommunityId: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 8)

            ForEach(communities) { community in
                communityAvatar(community)
            }

            Divider()
                .frame(width: 32)
                .foregroundStyle(AmenTheme.Colors.separatorSubtle)

            addButton

            Spacer()
        }
        .frame(width: 56)
        .padding(.horizontal, 4)
        .background {
            if reduceTransparency {
                AmenTheme.Colors.backgroundSecondary
            } else {
                Rectangle()
                    .fill(LiquidGlassTokens.blurThin)
                    .overlay {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                    }
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AmenTheme.Colors.separatorSubtle)
                .frame(width: 0.5)
        }
        .sheet(isPresented: $showCreateSheet) {
            CommunityCreateSheet(isPresented: $showCreateSheet) { newCommunityId in
                selectedCommunityId = newCommunityId
            }
        }
    }

    // MARK: - Community avatar button

    @ViewBuilder
    private func communityAvatar(_ community: SpacesCommunity) -> some View {
        let communityId = community.id ?? ""
        let isSelected = communityId == selectedCommunityId
        let unread = unreadByCommunity[communityId] ?? 0

        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.1) : Motion.liquidSpring) {
                selectedCommunityId = communityId
            }
            tooltipCommunityId = nil
        } label: {
            ZStack(alignment: .topTrailing) {
                SpaceAvatarView(
                    avatarURL: community.avatarURL,
                    title: community.name,
                    size: 42,
                    isShared: false
                )
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(AmenTheme.Colors.amenPurple, lineWidth: 2.5)
                    }
                }

                if unread > 0 {
                    Circle()
                        .fill(AmenTheme.Colors.amenPurple)
                        .frame(width: 10, height: 10)
                        .overlay {
                            Circle()
                                .stroke(AmenTheme.Colors.backgroundPrimary, lineWidth: 1.5)
                        }
                        .offset(x: 4, y: -4)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(reduceMotion ? .none : Motion.liquidSpring, value: isSelected)
        .accessibilityLabel("\(community.name)\(unread > 0 ? ", \(unread) unread" : "")")
        .accessibilityHint("Double-tap to switch to this community.")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .onLongPressGesture(minimumDuration: 0.4) {
            tooltipCommunityId = communityId
        }
        .popover(isPresented: Binding(
            get: { tooltipCommunityId == communityId },
            set: { if !$0 { tooltipCommunityId = nil } }
        )) {
            Text(community.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - Add button

    private var addButton: some View {
        Button {
            showCreateSheet = true
        } label: {
            ZStack {
                Circle()
                    .fill(AmenTheme.Colors.surfaceChip)
                    .frame(width: 42, height: 42)
                    .overlay {
                        Circle()
                            .stroke(AmenTheme.Colors.separatorSubtle, lineWidth: 0.5)
                    }
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create or join a community")
        .accessibilityHint("Opens the community creation sheet.")
    }
}

#if DEBUG
#Preview("CommunitySwitcherView") {
    @Previewable @State var selected = "c1"
    let communities: [SpacesCommunity] = [
        SpacesCommunity(name: "Hillside", handle: "hillside", avatarURL: nil,
                        ownerUserId: "u1", stripeConnectAccountId: nil,
                        createdAt: .init(date: .now)),
        SpacesCommunity(name: "Grace", handle: "grace", avatarURL: nil,
                        ownerUserId: "u1", stripeConnectAccountId: nil,
                        createdAt: .init(date: .now)),
    ]
    CommunitySwitcherView(
        selectedCommunityId: $selected,
        communities: communities,
        unreadByCommunity: ["c1": 3]
    )
    .frame(height: 400)
}
#endif
