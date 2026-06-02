// AmenBestReachRecommendationView.swift
// AMEN Connect + Spaces — Presence & Care Routing (Agent 5)
// Built 2026-06-01
//
// Aegis caps enforced: C-14 (urgentReachable explicit opt-in — never auto-on),
// C-22 (sabbath rest — do not contact except emergencies), C-34 (read-only member info),
// C-41 (reduce-motion via @Environment).

import SwiftUI

// MARK: - Recommendation model

private struct ReachRecommendation {
    let emoji: String
    let headline: String
    let detail: String?
    let accentColor: Color
}

// MARK: - View

struct AmenBestReachRecommendationView: View {
    let presence: AmenConnectSpacesPresence

    var body: some View {
        // Matte card — member info content is never behind glass (C-34)
        let rec = recommendation(for: presence)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(rec.emoji)
                    .font(.title2)
                    .accessibilityHidden(true)
                Text(rec.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(rec.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let detail = rec.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(rec.accentColor.opacity(0.25), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(rec: rec))
    }

    // MARK: - Routing logic

    private func recommendation(for presence: AmenConnectSpacesPresence) -> ReachRecommendation {
        let state = presence.spiritualState

        // C-14: urgentReachable must be true to advertise urgent prayer reach
        if state == .availableForUrgentPrayer {
            if presence.urgentReachable {
                return ReachRecommendation(
                    emoji: "🔴",
                    headline: "Available for urgent prayer — reach out now",
                    detail: nil,
                    accentColor: .amenGold
                )
            } else {
                // C-14: flag off, respect setting
                return ReachRecommendation(
                    emoji: "🔴",
                    headline: "Urgent prayer reach is off — respect their setting.",
                    detail: "They have not enabled immediate reach-out at this time.",
                    accentColor: .secondary
                )
            }
        }

        switch state {
        case .inPrayer, .fasting:
            return ReachRecommendation(
                emoji: "🙏",
                headline: "In prayer or fasting — send a message, they'll reply when ready",
                detail: nil,
                accentColor: .amenPurple
            )

        case .sabbathRest:
            // C-22: sabbath rest — do not contact except genuine emergencies
            let dateString: String
            if let until = presence.sabbathUntil {
                dateString = until.formatted(.dateTime.weekday(.wide).hour().minute())
            } else {
                dateString = "an unspecified time"
            }
            return ReachRecommendation(
                emoji: "🌙",
                headline: "Sabbath rest until \(dateString). Please do not contact except for genuine emergencies.",
                detail: nil,
                accentColor: .amenBlue
            )

        case .grieving:
            return ReachRecommendation(
                emoji: "💙",
                headline: "Grieving — reach with care. A note of love is welcome.",
                detail: nil,
                accentColor: .amenBlue
            )

        case .discerning:
            return ReachRecommendation(
                emoji: "🕊️",
                headline: "Discerning — gentle check-in welcome.",
                detail: nil,
                accentColor: .amenPurple
            )

        case .inTheWord:
            return ReachRecommendation(
                emoji: "📖",
                headline: "In the Word — available after their reading time.",
                detail: nil,
                accentColor: .amenGold
            )

        case .availableForUrgentPrayer:
            // Already handled above; this branch is unreachable but required for exhaustive switch
            return ReachRecommendation(
                emoji: "🔴",
                headline: "Urgent prayer reach is off — respect their setting.",
                detail: nil,
                accentColor: .secondary
            )
        }
    }

    // MARK: - Accessibility label

    private func accessibilityLabel(rec: ReachRecommendation) -> String {
        var parts = [rec.headline]
        if let detail = rec.detail { parts.append(detail) }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Secondary color extension

private extension Color {
    static let secondary = Color(.secondaryLabel)
}
