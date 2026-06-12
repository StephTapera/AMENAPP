// CrisisBulletinCard.swift
// AMEN — Global Resilience System
//
// Compact, collapsible card that renders a single CrisisBulletin.
// - Title row is always visible; body expands / collapses on tap.
// - Severity tint: info = blue, warning = yellow, critical/emergency = red.
// - Expired bulletins show an "(Expired)" badge but remain fully readable.
// - Feature-gated: returns EmptyView when crisisBulletinsEnabled is false.
// - Container uses .regularMaterial with a severity-tinted overlay (.glassEffect
//   polyfill via .background(.regularMaterial, in: RoundedRectangle) because
//   the .glassEffect() modifier requires iOS 26 Liquid Glass opt-in; the
//   material approach is safe across iOS 17+).
// - Full VoiceOver support on all interactive and informational elements.

import SwiftUI

// MARK: - CrisisBulletinCard

struct CrisisBulletinCard: View {

    // MARK: Input

    let bulletin: CrisisBulletin

    // MARK: State

    @State private var isExpanded: Bool = false
    @ObservedObject private var flags = GlobalResilienceFeatureFlags.shared

    // MARK: Computed

    private var isExpired: Bool {
        bulletin.expiresAt < Date()
    }

    private var severityColor: Color {
        switch bulletin.severity {
        case "info":                return .blue
        case "warning":             return .yellow
        case "critical", "emergency": return .red
        default:                    return .blue
        }
    }

    private var severityIcon: String {
        switch bulletin.severity {
        case "info":                return "info.circle.fill"
        case "warning":             return "exclamationmark.triangle.fill"
        case "critical", "emergency": return "exclamationmark.octagon.fill"
        default:                    return "info.circle.fill"
        }
    }

    // MARK: Body

    var body: some View {
        if flags.crisisBulletinsEnabled {
            cardContent
        }
        // EmptyView when feature is off (implicit via if-less path)
    }

    // MARK: Card content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if isExpanded {
                bodySection
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(severityColor.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(severityColor.opacity(0.30), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Crisis bulletin: \(bulletin.title). Severity: \(bulletin.severity)"
        )
        .accessibilityHint(
            isExpanded ? "Double tap to collapse." : "Double tap to expand details."
        )
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Header row

    private var headerRow: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                // Severity icon
                Image(systemName: severityIcon)
                    .foregroundStyle(severityColor)
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)

                // Title
                Text(bulletin.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Expired badge
                if isExpired {
                    Text("Expired")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color(.tertiarySystemFill))
                        )
                        .accessibilityLabel("Expired bulletin")
                }

                // Chevron expand/collapse indicator
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        // Accessibility for the header button is handled at the outer
        // accessibilityElement(children: .combine) level.
        .accessibilityHidden(true)
    }

    // MARK: Body section (expanded)

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.horizontal, 14)

            // Body text — text-first, no autoplay media.
            Text(bulletin.bodyText)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)

            // Publisher row
            publisherRow

        }
        .padding(.bottom, 14)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: Publisher row

    @ViewBuilder
    private var publisherRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            // Published-by label. VerifiedBadgeView requires a VerificationTier;
            // the org verification tier is not available in the bulletin contract,
            // so we surface the org name directly. When org tier lookup is added,
            // replace the Text with:
            //   VerifiedBadgeView(tier: resolvedTier)
            Text("Published by: \(bulletin.publishedByOrgId)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .accessibilityLabel("Published by organization \(bulletin.publishedByOrgId)")
    }
}

// MARK: - Preview

#Preview("Info bulletin") {
    CrisisBulletinCard(
        bulletin: CrisisBulletin(
            id: "preview-1",
            title: "Service update for East Africa region",
            bodyText: "Connectivity has been restored in the Nairobi corridor. Continue to expect intermittent delays for large media uploads.",
            severity: "info",
            regionScope: "KE",
            expiresAt: Date().addingTimeInterval(3600),
            lowDataOnly: false,
            publishedByOrgId: "org-123"
        )
    )
    .padding()
}

#Preview("Critical bulletin (expired)") {
    CrisisBulletinCard(
        bulletin: CrisisBulletin(
            id: "preview-2",
            title: "Critical: Flooding in coastal areas",
            bodyText: "Emergency services are actively responding. Avoid the coastal highway. Shelter in place if in designated flood zones.",
            severity: "critical",
            regionScope: "global",
            expiresAt: Date().addingTimeInterval(-60),   // expired
            lowDataOnly: false,
            publishedByOrgId: "org-relief-global"
        )
    )
    .padding()
}

#Preview("Warning bulletin") {
    CrisisBulletinCard(
        bulletin: CrisisBulletin(
            id: "preview-3",
            title: "Power outages reported in Southeast Asia",
            bodyText: "Several provinces are experiencing rolling power outages. Network latency may be elevated. Download content for offline use.",
            severity: "warning",
            regionScope: "PH",
            expiresAt: Date().addingTimeInterval(7200),
            lowDataOnly: true,
            publishedByOrgId: "org-tech-ministry"
        )
    )
    .padding()
}
