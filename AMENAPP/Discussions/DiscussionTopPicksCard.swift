// DiscussionTopPicksCard.swift
// AMENAPP — Discussions
//
// Large card used in the "Top Picks for You" hero carousel on the discovery surface.
// Maps to Apple Music's featured carousel card:
//   - Full-bleed group art / gradient hero
//   - Category chip overlay (top-left)
//   - Group name + member count (bottom, over a gradient scrim)
//   - Spring scale on press

import SwiftUI

struct DiscussionTopPicksCard: View {
    let group: CommunityGroup
    var width: CGFloat = 300
    var height: CGFloat = 180
    var onTap: (CommunityGroup) -> Void = { _ in }

    var body: some View {
        Button {
            onTap(group)
        } label: {
            ZStack(alignment: .bottomLeading) {
                // Background art
                artLayer

                // Bottom gradient scrim
                LinearGradient(
                    colors: [.clear, .black.opacity(0.60)],
                    startPoint: UnitPoint(x: 0.5, y: 0.3),
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                // Text overlay
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text("\(group.memberCount.formatted()) members")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.80))
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)

                // Category chip (top-left)
                VStack {
                    HStack {
                        categoryChip
                        Spacer()
                    }
                    Spacer()
                }
                .padding(12)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 5)
        }
        .buttonStyle(AmenPressStyle(scale: 0.965))
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var artLayer: some View {
        if let url = group.coverImageURL, !url.isEmpty {
            CachedAsyncImage(url: URL(string: url)) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                GroupGradientHeroView(groupId: group.id, groupName: group.name)
            }
        } else {
            GroupGradientHeroView(groupId: group.id, groupName: group.name)
        }
    }

    private var categoryChip: some View {
        HStack(spacing: 4) {
            Image(systemName: group.category.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(group.category.rawValue)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
    }
}

// MARK: - Preview

#Preview("Top Picks Card") {
    let group = CommunityGroup(
        id: "preview_001",
        name: "Morning Scripture Circle",
        description: "Daily Bible study",
        category: .bible,
        creatorId: "uid",
        memberCount: 1234,
        coverImageURL: nil,
        isPrivate: false,
        createdAt: Date(),
        rules: []
    )
    DiscussionTopPicksCard(group: group)
        .padding()
}
