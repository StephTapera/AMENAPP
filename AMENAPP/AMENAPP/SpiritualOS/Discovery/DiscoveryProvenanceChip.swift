// DiscoveryProvenanceChip.swift
// AMEN App — Spiritual OS / Community Discovery
//
// "Why you're seeing this" provenance chip — a small, non-interactive label that
// explains, in human terms, why a recommended item appears. It uses ONLY signals the
// discovery rails view model has already fetched (AmenDiscoveryRailsViewModel.load):
// continue-journey progress and church-match metadata. No new server calls, no new
// data pipeline.
//
// Design rules (match the discovery rails):
//   • Semantic colors only — adaptive across light/dark, Reduce Transparency,
//     and Increase Contrast. NO literal black/white, NO glass behind text.
//   • Dynamic Type via text styles.
//   • Renders nothing when there is no real signal (never a generic label).
//
// Target membership: this file is new — a human must add it to the AMENAPP target
// in Xcode before the canonical build (per repo build protocol: no agent pbxproj edits).

import SwiftUI

// MARK: - DiscoveryProvenanceChip

/// Compact, non-interactive "why you're seeing this" label.
struct DiscoveryProvenanceChip: View {

    let text: String
    var systemImage: String = "sparkles"

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.accentColor.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Why you're seeing this: \(text)")
    }
}

// MARK: - DiscoveryProvenance

/// Derives a provenance line from signals the rails view model already fetched.
/// Returns `nil` for non-personalized rows, or when a personalized row lacks a real
/// signal — callers render no chip rather than a generic placeholder.
enum DiscoveryProvenance {

    static func text(for railType: DiscoveryRailType, item: DiscoveryRailItem) -> String? {
        switch railType {
        case .continueJourney:
            // Continue-journey items carry a real progress signal for this user.
            guard item.progressFraction != nil else { return nil }
            return "You started this"

        case .peopleYouShouldMeet:
            // These rows are matched on the viewer's own churchId (see
            // fetchPeopleYouShouldMeet) — only label when that match is present.
            guard let churchId = item.metadata["churchId"], !churchId.isEmpty else { return nil }
            return "People at your church"

        default:
            // Editorial / non-personalized rails get no chip.
            return nil
        }
    }

    static func icon(for railType: DiscoveryRailType) -> String {
        switch railType {
        case .peopleYouShouldMeet: return "person.2.fill"
        case .continueJourney:     return "arrow.clockwise"
        default:                   return "sparkles"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Provenance chips") {
    VStack(alignment: .leading, spacing: 16) {
        DiscoveryProvenanceChip(text: "You started this", systemImage: "arrow.clockwise")
        DiscoveryProvenanceChip(text: "People at your church", systemImage: "person.2.fill")
    }
    .padding()
    .background(Color(.systemBackground))
}

#Preview("Provenance chips — Dark") {
    VStack(alignment: .leading, spacing: 16) {
        DiscoveryProvenanceChip(text: "You started this", systemImage: "arrow.clockwise")
        DiscoveryProvenanceChip(text: "People at your church", systemImage: "person.2.fill")
    }
    .padding()
    .background(Color(.systemBackground))
    .preferredColorScheme(.dark)
}
#endif
