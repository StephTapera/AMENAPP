// BereanTrustBadge.swift
// AMENAPP
//
// Inline trust-level badge for Berean AI responses.
// Shows a compact icon + label + score, tappable to reveal the
// full explanation in a popover. Respects Reduce Motion and Dynamic Type.

import SwiftUI

// MARK: - BereanResponseTrustLevel

enum BereanResponseTrustLevel {
    case verified
    case mostlyVerified
    case partiallyVerified
    case unverified

    /// Human-readable label.
    var label: String {
        switch self {
        case .verified:          return "Verified"
        case .mostlyVerified:    return "Mostly Verified"
        case .partiallyVerified: return "Partially Verified"
        case .unverified:        return "Unverified"
        }
    }

    /// Semantic color for this trust level.
    var color: Color {
        switch self {
        case .verified:          return .green
        case .mostlyVerified:    return .blue
        case .partiallyVerified: return .orange
        case .unverified:        return .gray
        }
    }

    /// SF Symbol name for this trust level.
    var icon: String {
        switch self {
        case .verified:          return "checkmark.seal.fill"
        case .mostlyVerified:    return "checkmark.seal"
        case .partiallyVerified: return "questionmark.circle"
        case .unverified:        return "exclamationmark.circle"
        }
    }

    /// Derives the appropriate trust level from a 0.0-1.0 confidence score.
    static func from(score: Double) -> BereanResponseTrustLevel {
        switch score {
        case 0.8...:  return .verified
        case 0.6...:  return .mostlyVerified
        case 0.4...:  return .partiallyVerified
        default:      return .unverified
        }
    }
}

// MARK: - BereanTrustBadge

/// Compact badge showing the Berean trust level for an AI-generated response.
/// Tap the badge to see the explanation in a popover.
struct BereanTrustBadge: View {
    let trustLevel: BereanResponseTrustLevel
    let score: Double
    let explanation: String

    @State private var showingPopover = false
    @State private var pulseScale: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            showingPopover = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: trustLevel.icon)
                    .foregroundStyle(trustLevel.color)
                    .scaleEffect(pulseScale)

                Text(trustLevel.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(trustLevel.color)

                Text(".")
                    .foregroundStyle(Color(.tertiaryLabel))

                Text("\(Int(score * 100))%")
                    .foregroundStyle(Color(.secondaryLabel))
            }
            .font(.caption)
            .dynamicTypeSize(.small ... .accessibility3)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(trustLevel.color.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Trust level: \(trustLevel.label), score \(Int(score * 100)) percent")
        .accessibilityHint("Double-tap for explanation")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 1.4)
                .repeatForever(autoreverses: true)
            ) {
                pulseScale = 1.12
            }
        }
        .popover(isPresented: $showingPopover) {
            TrustExplanationPopover(trustLevel: trustLevel, score: score, explanation: explanation)
        }
    }
}

// MARK: - TrustExplanationPopover

/// Popover content showing the full trust explanation.
private struct TrustExplanationPopover: View {
    let trustLevel: BereanResponseTrustLevel
    let score: Double
    let explanation: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: trustLevel.icon)
                    .font(.title3)
                    .foregroundStyle(trustLevel.color)
                Text(trustLevel.label)
                    .font(.headline)
                    .foregroundStyle(trustLevel.color)
                Spacer()
                Text("\(Int(score * 100))% confidence")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }

            Divider()

            Text(explanation)
                .font(.body)
                .dynamicTypeSize(.small ... .accessibility3)
                .foregroundStyle(Color(.label))
                .fixedSize(horizontal: false, vertical: true)

            Button("Dismiss") { dismiss() }
                .font(.callout.weight(.medium))
                .foregroundStyle(trustLevel.color)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(minWidth: 280, maxWidth: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - TrustBadgeRow

/// Horizontal row composing a "Berean Trust" label with the inline BereanTrustBadge.
/// Append this to any BereanResponse view to surface the trust signal.
struct TrustBadgeRow: View {
    let trustLevel: BereanResponseTrustLevel
    let score: Double
    let explanation: String

    var body: some View {
        HStack(spacing: 8) {
            Text("Berean Trust")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(Color(.tertiaryLabel))
                .dynamicTypeSize(.small ... .accessibility3)

            BereanTrustBadge(
                trustLevel: trustLevel,
                score: score,
                explanation: explanation
            )

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Previews

#Preview("All trust levels") {
    VStack(alignment: .leading, spacing: 16) {
        ForEach([
            (BereanResponseTrustLevel.verified,          0.92, "Multiple cross-referenced sources confirm this interpretation."),
            (BereanResponseTrustLevel.mostlyVerified,    0.71, "Mainstream consensus with one minor dissenting tradition noted."),
            (BereanResponseTrustLevel.partiallyVerified, 0.52, "Some supporting evidence; competing interpretations exist."),
            (BereanResponseTrustLevel.unverified,        0.20, "Insufficient scriptural support found for this claim.")
        ], id: \.0.label) { level, score, explanation in
            TrustBadgeRow(trustLevel: level, score: score, explanation: explanation)
        }
    }
    .padding(24)
    .background(Color(.systemGroupedBackground))
}
