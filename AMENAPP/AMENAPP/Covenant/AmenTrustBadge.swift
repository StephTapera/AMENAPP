import SwiftUI

// MARK: - Trust Badge
// Data-backed badges displayed on Covenants, rooms, and creator profiles.
// Never faked — all types require server-set fields to render.

struct AmenTrustBadge: View {
    let type: TrustBadgeType
    var size: BadgeSize = .standard

    enum BadgeSize {
        case compact, standard, large
        var iconSize: CGFloat    { switch self { case .compact: 10; case .standard: 12; case .large: 16 } }
        var textFont: Font       { switch self { case .compact: .systemScaled(9, weight: .semibold); case .standard: .caption.weight(.semibold); case .large: .subheadline.weight(.semibold) } }
        var padding: EdgeInsets  { switch self { case .compact: .init(top: 3, leading: 6, bottom: 3, trailing: 6); case .standard: .init(top: 4, leading: 8, bottom: 4, trailing: 8); case .large: .init(top: 6, leading: 12, bottom: 6, trailing: 12) } }
        var showLabel: Bool      { self != .compact }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: type.icon)
                .font(.systemScaled(size.iconSize, weight: .semibold))
                .foregroundStyle(badgeColor)
            if size.showLabel {
                Text(type.displayName)
                    .font(size.textFont)
                    .foregroundStyle(badgeColor)
            }
        }
        .padding(size.padding)
        .background(
            Capsule()
                .fill(badgeColor.opacity(0.12))
                .overlay(Capsule().stroke(badgeColor.opacity(0.25), lineWidth: 0.5))
        )
        .accessibilityLabel(type.displayName)
    }

    private var badgeColor: Color {
        switch type {
        case .verifiedCreator:  return .blue
        case .churchVerified:   return .purple
        case .ministryVerified: return .indigo
        case .healthyCommunity: return .green
        case .newCommunity:     return .orange
        case .moderatedRoom:    return .teal
        case .paidMembersOnly:  return Color(uiColor: .systemYellow)
        case .sensitiveTopic:   return .red
        }
    }
}

// MARK: - Trust Badge Row (for Covenant header, profile, etc.)

struct AmenTrustBadgeRow: View {
    let badges: [TrustBadgeType]
    var size: AmenTrustBadge.BadgeSize = .standard

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(badges, id: \.self) { badge in
                    AmenTrustBadge(type: badge, size: size)
                }
            }
        }
    }
}

// MARK: - Verified Checkmark (inline, next to name)

struct VerifiedCreatorMark: View {
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.systemScaled(13))
            .foregroundStyle(Color.blue)
            .accessibilityLabel("Verified Creator")
    }
}
