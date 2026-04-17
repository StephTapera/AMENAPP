//
//  TrustExplainerView.swift
//  AMENAPP
//
//  Compact card explaining why a message was routed to requests vs primary inbox.
//  Shows context signals: reason, trust level badge, and brief explanation.
//

import SwiftUI

struct TrustExplainerView: View {
    let explanation: MessageRequestExplanation

    var body: some View {
        HStack(spacing: 10) {
            // Trust level icon
            trustLevelIcon
                .frame(width: 28, height: 28)
                .background(trustLevelColor.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(explanation.headline)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black)

                Text(explanation.detail)
                    .font(.system(size: 12))
                    .foregroundColor(.black.opacity(0.5))
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.03))
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Trust Level Icon

    @ViewBuilder
    private var trustLevelIcon: some View {
        // CRITICAL FIX: Color-only state. Each image communicates trust level via
        // color (green/orange/yellow/red) with no text alternative. Add an
        // accessibilityLabel describing the trust level in words so VoiceOver
        // users receive the same information as sighted users.
        switch explanation.trustLevel {
        case .high:
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 13))
                .foregroundColor(.green)
                .accessibilityLabel("Trusted sender")
        case .medium:
            Image(systemName: "person.badge.clock.fill")
                .font(.system(size: 13))
                .foregroundColor(.orange)
                .accessibilityLabel("Pending trust")
        case .low:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundColor(.yellow)
                .accessibilityLabel("Low trust — review recommended")
        case .spam:
            Image(systemName: "xmark.shield.fill")
                .font(.system(size: 13))
                .foregroundColor(.red)
                .accessibilityLabel("Filtered — likely spam")
        }
    }

    private var trustLevelColor: Color {
        switch explanation.trustLevel {
        case .high: return .green
        case .medium: return .orange
        case .low: return .yellow
        case .spam: return .red
        }
    }
}

// MARK: - Compact Inline Variant

/// A smaller inline badge variant for conversation rows.
struct TrustLevelBadge: View {
    let trustLevel: MessageRequestTrustLevel

    var body: some View {
        HStack(spacing: 3) {
            // CRITICAL FIX: Color-only dot. Hide it from AX — the Text label already
            // conveys the trust level. Without this, VoiceOver announces "Circle" before
            // the label, adding noise without context.
            Circle()
                .fill(badgeColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(badgeColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(badgeColor.opacity(0.1))
        )
        // Expose the badge as a single accessible element with a clear label
        // so VoiceOver announces e.g. "Trust level: Trusted" rather than
        // reading the inner text and hidden circle separately.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trust level: \(label)")
    }

    private var label: String {
        switch trustLevel {
        case .high: return "Trusted"
        case .medium: return "Request"
        case .low: return "Review"
        case .spam: return "Filtered"
        }
    }

    private var badgeColor: Color {
        switch trustLevel {
        case .high: return .green
        case .medium: return .orange
        case .low: return .yellow
        case .spam: return .red
        }
    }
}
