// PrayerGraphCardView.swift
// AMENAPP — Living Intelligence — Prayer Graph Card
// Displays a prayer connection IntelligenceCard.
// Rules:
//   - Prayer title anonymized if needed (caller provides display title)
//   - "Add Your Prayer" button calls action.addToPrayer handler
//   - Loop closing: if card has loopParentId, shows follow-up context
//   - Lament frame: muted compassionate style when lamentFrame == true
//   - NO counts of any kind
//   - Liquid Glass material

import SwiftUI

// MARK: - Model

struct PrayerGraphCard: Identifiable {
    let id: String
    let title: String            // may be "Anonymous prayer request" if isAnonymous
    let summary: [String]
    let matchReasons: [String]
    let prayerRequestId: String  // backingEntity.id

    // Loop closing
    let loopParentId: String?    // non-nil if user has prayed before
    let priorPrayedAt: Date?

    // Lament frame
    let lamentFrame: Bool

    let createdAt: Date
    let expiresAt: Date
}

// MARK: - Action Handler Protocol

protocol PrayerGraphCardDelegate: AnyObject {
    func addToPrayer(prayerRequestId: String)
    func openPrayer(prayerRequestId: String)
}

// MARK: - Main View

struct PrayerGraphCardView: View {
    let card: PrayerGraphCard
    var delegate: (any PrayerGraphCardDelegate)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingMatchReasons = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Loop-closing banner (only when following up on a prior prayer)
            if let loopParentId = card.loopParentId, !loopParentId.isEmpty {
                loopClosingBanner
            }

            // Header
            cardHeader

            Divider()
                .opacity(lamentOpacity(0.2))
                .padding(.horizontal, 16)

            // Summary
            VStack(alignment: .leading, spacing: 6) {
                ForEach(card.summary.prefix(3), id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: card.lamentFrame ? "heart" : "hands.sparkles")
                            .font(.caption2)
                            .foregroundStyle(lamentAccent)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                        Text(bullet)
                            .font(.subheadline)
                            .foregroundStyle(lamentForeground)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Match reasons (no counts)
            if !card.matchReasons.isEmpty {
                matchReasonRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider()
                .opacity(lamentOpacity(0.15))
                .padding(.horizontal, 16)

            // Actions
            actionRow
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(lamentBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: - Loop Closing Banner

    private var loopClosingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.medium))
                .foregroundStyle(lamentAccent)
                .accessibilityHidden(true)

            if let priorDate = card.priorPrayedAt {
                Text("Following up on your prayer from \(priorDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(lamentAccent)
            } else {
                Text("Continuing your prayer journey")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(lamentAccent)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            lamentAccent.opacity(0.08),
            in: UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20,
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            card.priorPrayedAt != nil
            ? "Continuing your prayer from \(card.priorPrayedAt!.formatted(date: .abbreviated, time: .omitted))"
            : "Continuing your prayer journey"
        )
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                // Tier indicator
                Text("Prayer Request")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(lamentAccent)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .accessibilityHidden(true)

                Text(card.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(lamentForeground)
                    .lineLimit(3)
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer()

            Image(systemName: card.lamentFrame ? "heart.fill" : "hands.sparkles.fill")
                .font(.title2)
                .foregroundStyle(lamentAccent)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Match Reason Row (no counts)

    private var matchReasonRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(card.matchReasons.prefix(3), id: \.self) { reason in
                    Text(reason)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(lamentForeground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                        )
                        .accessibilityLabel("Why this matched: \(reason)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Why this prayer request was surfaced for you")
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 12) {
            // Primary: Add Your Prayer
            Button {
                delegate?.addToPrayer(prayerRequestId: card.prayerRequestId)
            } label: {
                Label("Add Your Prayer", systemImage: "hands.sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(lamentAccent)
                    )
            }
            .accessibilityLabel("Add your prayer to this request")
            .accessibilityHint("Joins you in praying for this need")

            // Secondary: Open Prayer
            Button {
                delegate?.openPrayer(prayerRequestId: card.prayerRequestId)
            } label: {
                Image(systemName: "arrow.forward.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
            }
            .accessibilityLabel("Open prayer request")

            Spacer()
        }
    }

    // MARK: - Lament Styling Helpers

    private func lamentOpacity(_ base: Double) -> Double {
        card.lamentFrame ? base * 0.7 : base
    }

    private var lamentAccent: Color {
        card.lamentFrame
            ? Color(hex: "#7A6B8A")   // muted purple — compassionate
            : Color(hex: "#A78843")   // amen gold
    }

    private var lamentForeground: Color {
        card.lamentFrame
            ? Color.primary.opacity(0.85)
            : Color.primary
    }

    private var cardBackground: some ShapeStyle {
        if card.lamentFrame {
            return AnyShapeStyle(.regularMaterial)
        }
        return AnyShapeStyle(.regularMaterial)
    }

    private var lamentBorder: some ShapeStyle {
        card.lamentFrame
            ? AnyShapeStyle(Color(hex: "#7A6B8A").opacity(0.25))
            : AnyShapeStyle(Color.clear)
    }
}

// MARK: - Preview

#if DEBUG
private final class PreviewDelegate: PrayerGraphCardDelegate {
    func addToPrayer(prayerRequestId: String) {}
    func openPrayer(prayerRequestId: String) {}
}

private enum PrayerGraphCardPreviewSupport {
    static let delegate = PreviewDelegate()
}

#Preview("Standard Prayer Card") {
    PrayerGraphCardView(
        card: PrayerGraphCard(
            id: "preview_prayer_1",
            title: "Healing for my mother",
            summary: ["From your church community", "Similar to your prayer history"],
            matchReasons: ["From your church community", "Similar to your prayer history"],
            prayerRequestId: "prayer_abc123",
            loopParentId: nil,
            priorPrayedAt: nil,
            lamentFrame: false,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400 * 7)
        ),
        delegate: PrayerGraphCardPreviewSupport.delegate
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Lament Frame + Loop Closing") {
    PrayerGraphCardView(
        card: PrayerGraphCard(
            id: "preview_prayer_2",
            title: "Anonymous prayer request",
            summary: ["From your community", "Continuing your journey"],
            matchReasons: ["From your community"],
            prayerRequestId: "prayer_xyz456",
            loopParentId: "prayer_prior_uid_xyz456",
            priorPrayedAt: Calendar.current.date(byAdding: .day, value: -10, to: Date()),
            lamentFrame: true,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400 * 7)
        ),
        delegate: PrayerGraphCardPreviewSupport.delegate
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
#endif
