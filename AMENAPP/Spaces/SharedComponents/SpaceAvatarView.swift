// SpaceAvatarView.swift
// AMENAPP — Spaces v2 Shared Components (Agent C)
//
// Circular avatar for Space and Community tiles.
// Shows AsyncImage if avatarURL is provided, falls back to initials from title.
// Optional LinkedCommunityGlyph badge in bottom-right when isShared == true.
// Import this — B/D/E/F never re-implement.
// See CONTRACT_C.md for the full API.

import SwiftUI

/// Circular avatar for Spaces and Communities.
/// AsyncImage with initials fallback. Optional LinkedCommunityGlyph badge.
///
/// Usage:
/// ```swift
/// SpaceAvatarView(avatarURL: space.avatarURL, title: space.title, size: 44, isShared: !space.sharedWith.isEmpty)
/// ```
struct SpaceAvatarView: View {

    // MARK: - Parameters (CONTRACT_C public API)

    let avatarURL: String?
    let title: String
    let size: CGFloat
    let isShared: Bool
    /// Name of the first shared community — shown in LinkedCommunityGlyph popover.
    var sharedCommunityName: String = ""

    // MARK: - Computed

    private var initials: String {
        let words = title.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        let letters = words.prefix(2).compactMap { $0.first?.uppercased() }
        return letters.joined()
    }

    private var glyphSize: CGFloat {
        if size <= 32 { return 10 }
        if size <= 48 { return 13 }
        return 16
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarCircle
            if isShared {
                LinkedCommunityGlyph(size: glyphSize, communityName: sharedCommunityName)
                    .offset(x: 4, y: 4)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) avatar\(isShared ? ", shared community" : "")")
    }

    // MARK: - Avatar circle

    @ViewBuilder
    private var avatarCircle: some View {
        Group {
            if let urlString = avatarURL, !urlString.isEmpty, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsCircle
                    }
                }
            } else {
                initialsCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
        }
    }

    private var initialsCircle: some View {
        ZStack {
            if reduceTransparency {
                Circle()
                    .fill(AmenTheme.Colors.surfaceChip)
            } else {
                Circle()
                    .fill(LiquidGlassTokens.blurThin)
                    .overlay {
                        Circle()
                            .fill(AmenTheme.Colors.amenPurple.opacity(0.12))
                    }
            }
            Text(initials)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenPurple)
        }
    }
}

#if DEBUG
#Preview("SpaceAvatarView") {
    VStack(spacing: 24) {
        SpaceAvatarView(avatarURL: nil, title: "Hillside Community", size: 56, isShared: false)
        SpaceAvatarView(avatarURL: nil, title: "Grace Fellowship", size: 44, isShared: true, sharedCommunityName: "Cornerstone")
        SpaceAvatarView(avatarURL: nil, title: "Romans Study", size: 32, isShared: false)
    }
    .padding()
}
#endif
