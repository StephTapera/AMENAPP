// AmenBereanProvenanceBanner.swift
// AMEN App — CommunityOS / Berean
//
// Phase 2 — Agent A4 (Berean Integration)
// Reusable "From Berean" attribution banner shown on any object converted from
// a Berean AI output.
//
// Design rules (C3):
//   - System semantic colors only — no custom hex, no amenGold.
//   - Compact, subtle: does not dominate the containing card.
//   - Tappable when onViewSource is provided — tapping opens the original conversation.
//   - Accessibility: combined element with clear label and optional hint.
//   - Compatible with both light (standard feed) and dark (in-Berean) backgrounds.
//
// Two public surfaces:
//   AmenBereanProvenanceBanner  — standard capsule attribution chip (light background)
//   AmenBereanProvenanceInline  — single-line inline variant for dense list rows

import SwiftUI

// MARK: - AmenBereanProvenanceBanner

/// Capsule attribution chip shown on converted objects.
/// Reads the `SpawnProvenance` written at conversion time and renders:
///   [brain.head.profile] "Insight from Berean" [chevron.right — if tappable]
///
/// Place this at the top of a card or post that was created from a Berean capture.
/// Do not show it on objects where provenance.sourceType is not "bereanInsight".
struct AmenBereanProvenanceBanner: View {

    // MARK: Inputs

    /// Provenance block read from the converted object.
    let provenance: SpawnProvenance

    /// When provided, the banner becomes tappable and shows a disclosure chevron.
    /// Callback should open the original Berean conversation identified by `provenance.sourceRef`.
    var onViewSource: (() -> Void)?

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Computed

    /// True when this provenance was produced by a Berean conversion.
    private var isBereanProvenance: Bool {
        provenance.sourceType == "bereanInsight"
    }

    private var intentDisplayName: String {
        switch provenance.intent {
        case "share":    return "shared insight"
        case "discuss":  return "discussion"
        case "pray":     return "prayer"
        case "study":    return "study"
        case "teach":    return "teaching"
        case "mentor":   return "mentorship topic"
        case "ask":      return "question"
        default:         return "insight"
        }
    }

    // MARK: - Body

    var body: some View {
        if isBereanProvenance {
            if let handler = onViewSource {
                Button(action: handler) {
                    bannerContent(tappable: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Insight from Berean — \(intentDisplayName)")
                .accessibilityHint("Tap to view the original Berean conversation")
            } else {
                bannerContent(tappable: false)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Insight from Berean — \(intentDisplayName)")
            }
        }
    }

    // MARK: - Banner Content

    private func bannerContent(tappable: Bool) -> some View {
        HStack(spacing: 5) {
            // Berean brain icon
            Image(systemName: "brain.head.profile")
                .font(.systemScaled(11, weight: .medium))
                .foregroundStyle(Color.accentColor)

            // Attribution text
            Text("Insight from Berean")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color(uiColor: .secondaryLabel))

            // Tappable disclosure chevron
            if tappable {
                Image(systemName: "chevron.right")
                    .font(.systemScaled(10, weight: .medium))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
        )
        .fixedSize()
    }
}

// MARK: - AmenBereanProvenanceInline

/// Single-line inline variant for dense list rows and thread headers.
/// Renders as plain text with the Berean icon — no background capsule.
/// Use this where the full banner would visually overwhelm the row.
struct AmenBereanProvenanceInline: View {

    // MARK: Inputs

    let provenance: SpawnProvenance

    // MARK: - Body

    var body: some View {
        if provenance.sourceType == "bereanInsight" {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                    .font(.systemScaled(10, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                Text("Berean")
                    .font(.caption2)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("From Berean")
        }
    }
}

// MARK: - View Extension

extension View {
    /// Adds a `AmenBereanProvenanceBanner` above this view if the provenance is from Berean.
    /// No-op when `provenance` is nil or not from Berean.
    ///
    /// Usage:
    /// ```swift
    /// PostCardView(post: post)
    ///     .amenBereanProvenance(post.provenance)
    /// ```
    func amenBereanProvenance(
        _ provenance: SpawnProvenance?,
        onViewSource: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let p = provenance {
                AmenBereanProvenanceBanner(provenance: p, onViewSource: onViewSource)
            }
            self
        }
    }
}

// MARK: - Preview

#Preview("Berean Provenance Banner — tappable") {
    let provenance = SpawnProvenance(
        sourceType:    "bereanInsight",
        sourceRef:     "/bereanConversations/session_abc123",
        sourceOwnerId: nil,
        intent:        "share",
        createdAt:     Date()
    )
    return VStack(alignment: .leading, spacing: 16) {
        AmenBereanProvenanceBanner(provenance: provenance, onViewSource: {})
        AmenBereanProvenanceBanner(provenance: provenance, onViewSource: nil)
        AmenBereanProvenanceInline(provenance: provenance)
    }
    .padding(24)
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Berean Provenance Banner — non-Berean (no-op)") {
    let provenance = SpawnProvenance(
        sourceType:    "post",
        sourceRef:     "/posts/abc123",
        sourceOwnerId: "uid_123",
        intent:        "discuss",
        createdAt:     Date()
    )
    return AmenBereanProvenanceBanner(provenance: provenance)
        .padding(24)
        .background(Color(uiColor: .systemGroupedBackground))
}
