// SharedCommunityBanner.swift
// AMENAPP — Spaces v2 Shared Components (Agent C)
//
// Glass pill banner showing cross-community sharing signal.
// Driven by single denormalized fields — no Firestore reads inside.
// Import this — never re-implement. See CONTRACT_C.md for full API.
//
// Two styles:
//   - Pill (compact): mode-based, used in Space rows and composer.
//   - Hero (expanded): communityName + avatarURL + memberCount, used at top of SpaceDetailView.

import SwiftUI

// MARK: - SharedCommunityBanner (pill style — CONTRACT_C primary API)

/// Glass pill banner showing cross-community sharing signal.
/// Driven by single denormalized fields — no Firestore reads inside.
/// Import this — never re-implement.
struct SharedCommunityBanner: View {

    // MARK: - Mode

    /// Mode drives the copy and semantic meaning of the banner.
    enum Mode {
        /// "Shared with [Community]."
        case sharedWith(communityName: String)
        /// "N members are from [Community]."
        case membersFrom(count: Int, communityName: String)

        var labelText: String {
            switch self {
            case .sharedWith(let name):
                return "Shared with \(name)."
            case .membersFrom(let count, let name):
                return "\(count) \(count == 1 ? "member is" : "members are") from \(name)."
            }
        }
    }

    // MARK: - Parameters

    let mode: Mode

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Body

    var body: some View {
        HStack(spacing: 6) {
            LinkedGlyph(size: .small)

            Text(mode.labelText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if reduceTransparency {
                Capsule(style: .continuous)
                    .fill(AmenTheme.Colors.surfaceChip)
            } else {
                Capsule(style: .continuous)
                    .fill(LiquidGlassTokens.blurThin)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    }
            }
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(mode.labelText)
    }
}

// MARK: - SharedCommunityBannerHero (hero-profile expanded style — CONTRACT_C extended API)

/// Hero-profile style shared-community banner for SpaceDetailView header.
/// Shows community avatar + name + member count + LinkedCommunityGlyph.
///
/// Usage:
/// ```swift
/// SharedCommunityBannerHero(
///     communityName: "Hillside Community",
///     communityAvatarURL: community.avatarURL,
///     externalMemberCount: 7,
///     spaceType: .bibleStudy
/// )
/// ```
struct SharedCommunityBannerHero: View {

    // MARK: - Parameters (CONTRACT_C public API)

    let communityName: String
    let communityAvatarURL: String?
    let externalMemberCount: Int
    let spaceType: AmenSpace.SpaceType

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Computed

    private var typeLabel: String {
        switch spaceType {
        case .chat:         return "discussion"
        case .bibleStudy:   return "study"
        case .group:        return "group"
        case .announcement: return "announcement feed"
        }
    }

    private var bannerText: String {
        "This \(typeLabel) is shared with \(communityName)"
    }

    private var memberSubtext: String {
        "\(externalMemberCount) \(externalMemberCount == 1 ? "member" : "members") from this community"
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            // Community avatar
            SpaceAvatarView(
                avatarURL: communityAvatarURL,
                title: communityName,
                size: 36,
                isShared: false
            )

            // Text stack
            VStack(alignment: .leading, spacing: 2) {
                Text(bannerText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(2)

                if externalMemberCount > 0 {
                    Text(memberSubtext)
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
            }

            Spacer(minLength: 0)

            // Linked glyph
            LinkedCommunityGlyph(
                size: 16,
                communityName: communityName
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceChip)
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
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bannerText). \(externalMemberCount > 0 ? memberSubtext : "")")
    }
}

#if DEBUG
#Preview("SharedCommunityBanner Modes") {
    VStack(spacing: 12) {
        SharedCommunityBanner(mode: .sharedWith(communityName: "Hillside Community"))
        SharedCommunityBanner(mode: .membersFrom(count: 7, communityName: "Grace Fellowship"))
        SharedCommunityBanner(mode: .membersFrom(count: 1, communityName: "Cornerstone"))
        Divider()
        SharedCommunityBannerHero(
            communityName: "Hillside Community",
            communityAvatarURL: nil,
            externalMemberCount: 7,
            spaceType: .bibleStudy
        )
        SharedCommunityBannerHero(
            communityName: "Grace Fellowship",
            communityAvatarURL: nil,
            externalMemberCount: 0,
            spaceType: .chat
        )
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}
#endif
