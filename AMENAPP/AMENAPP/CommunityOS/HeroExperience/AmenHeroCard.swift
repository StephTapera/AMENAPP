// AmenHeroCard.swift
// AMEN App — Community OS › Hero Experience
//
// Phase 5 Agent D2 — Hero Experience
// A floating white card that combines a compact AmenHeroHeader with arbitrary
// footer content below the photo band.
//
// Design contract (C3):
//   - Outer card: white fill + AmenShadow.card + AmenRadius.card (28pt) .continuous
//   - Photo band: AmenHeroHeader at .compact height (200pt)
//   - Footer: white background, 16pt padding all sides
//   - Tap target: full card, minimum 44pt tall, contentShape covers the whole card
//   - NO glass-on-glass: footer area is plain white, never glassEffect
//   - Separates from AmenUniversalHeroCard (expandable) by being tap-to-navigate
//     rather than expand-in-place

import SwiftUI

// MARK: — AmenHeroCard

/// A floating white card with a compact photo hero at the top and
/// caller-supplied footer content below.
///
/// Use this for list-style discovery cards where tapping navigates
/// to a detail surface (not expands in place — use AmenUniversalHeroCard
/// for the in-place expansion pattern).
///
/// Usage:
/// ```swift
/// AmenHeroCard(
///     imageUrl: church.coverImageUrl,
///     title: church.name,
///     subtitle: church.denomination,
///     badge: church.isVerified ? "Verified" : nil
/// ) {
///     HStack { Text("9:00 AM"); Spacer(); Text("3.2 mi") }
/// } onTap: {
///     router.push(.church(church.id))
/// }
/// ```
struct AmenHeroCard<Footer: View>: View {

    let imageUrl: String?
    let title: String
    let subtitle: String?
    let badge: String?
    @ViewBuilder let footer: () -> Footer
    var onTap: (() -> Void)?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // Photo hero — compact height (200pt)
            AmenHeroHeader(
                imageUrl: imageUrl,
                title: title,
                subtitle: subtitle,
                badge: badge,
                height: .compact
            ) {
                EmptyView()
            }

            // Footer content — white panel below the photo band
            VStack(alignment: .leading, spacing: 8) {
                footer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
        }
        .amenCard()
        .contentShape(
            RoundedRectangle(cornerRadius: AmenRadius.card, style: .continuous)
        )
        .onTapGesture {
            onTap?()
        }
        // Accessibility: treat the whole card as a single button
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(onTap != nil ? .isButton : [])
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var parts = [title]
        if let subtitle { parts.append(subtitle) }
        if let badge { parts.append(badge) }
        return parts.joined(separator: ", ")
    }
}

// MARK: — Preview

#if DEBUG

private struct SampleFooter: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("9:00 AM")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))
                Text("Service")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 28)

            VStack(spacing: 2) {
                Text("3.2 mi")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))
                Text("Distance")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 28)

            VStack(spacing: 2) {
                Text("850")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))
                Text("Members")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview("AmenHeroCard — church") {
    ScrollView {
        VStack(spacing: 16) {
            AmenHeroCard(
                imageUrl: nil,
                title: "Crosspoint Church",
                subtitle: "Non-Denominational · Phoenix, AZ",
                badge: "Verified"
            ) {
                SampleFooter()
            } onTap: {}

            AmenHeroCard(
                imageUrl: nil,
                title: "Grace Fellowship",
                subtitle: nil,
                badge: nil
            ) {
                Text("Sunday 10:30 AM")
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
        }
        .padding(20)
    }
    .background(Color(uiColor: .systemGroupedBackground))
}
#endif
