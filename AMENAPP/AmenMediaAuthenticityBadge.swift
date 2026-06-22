// AmenMediaAuthenticityBadge.swift
// AMENAPP
//
// Compact inline authenticity badge for media items.
// Tapping opens the full ProvenanceTrustPanel for detailed provenance context.
// Gated by AMENFeatureFlags.shared.mediaAuthenticityBadgesEnabled.

import SwiftUI

// MARK: - AmenMediaAuthenticityBadge

/// Compact pill badge showing the authenticity state of a media item.
struct AmenMediaAuthenticityBadge: View {
    let label: AuthenticityLabel
    var compact: Bool = true
    var onTap: (() -> Void)? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if AMENFeatureFlags.shared.mediaAuthenticityBadgesEnabled {
            badgeContent
        }
    }

    @ViewBuilder
    private var badgeContent: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: label.systemIcon)
                    .font(.systemScaled(compact ? 10 : 12, weight: .semibold))
                    .accessibilityHidden(true)
                Text(label.shortBadgeTitle)
                    .font(.systemScaled(compact ? 11 : 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(badgeForeground)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 4 : 6)
            .background(badgeAccentColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(badgeAccentColor.opacity(0.35), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityLabel(label.title)
        .accessibilityHint(onTap != nil ? "Tap to view media origin details" : "")
    }

    private var badgeForeground: Color {
        switch label.kind {
        case .syntheticWarning:
            return .red
        case .pendingReview:
            return Color(.secondaryLabel)
        case .realMedia, .creatorVerified, .communityVerified, .churchMedia:
            return Color(red: 0.18, green: 0.55, blue: 0.34)
        default:
            return .primary
        }
    }

    private var badgeAccentColor: Color {
        switch label.kind {
        case .syntheticWarning: return .red
        case .realMedia, .creatorVerified, .communityVerified, .churchMedia: return .green
        default: return Color(.tertiaryLabel)
        }
    }
}

// MARK: - AmenMediaAuthenticityBadgeRow

/// Compact horizontal row of up to 3 authenticity badges for a single media item.
struct AmenMediaAuthenticityBadgeRow: View {
    let labels: [AuthenticityLabel]
    var onTapBadge: ((AuthenticityLabel) -> Void)? = nil

    var body: some View {
        if !labels.isEmpty {
            HStack(spacing: 6) {
                ForEach(labels.prefix(3)) { label in
                    AmenMediaAuthenticityBadge(label: label) {
                        onTapBadge?(label)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(labels.prefix(3).map(\.title).joined(separator: ", "))
        }
    }
}

// MARK: - AuthenticityLabel extension

private extension AuthenticityLabel {
    var shortBadgeTitle: String {
        switch kind {
        case .realMedia:             return "Real"
        case .creatorVerified:       return "Verified"
        case .communityVerified:     return "Community"
        case .churchMedia:           return "Church"
        case .editedRealFootage:     return "Edited"
        case .aiAssistedCaptions:    return "AI Captions"
        case .aiAssistedTranslation: return "AI Translation"
        case .transcriptApproved:    return "Transcript ✓"
        case .pendingReview:         return "Pending"
        case .syntheticWarning:      return "Synthetic Risk"
        }
    }
}
