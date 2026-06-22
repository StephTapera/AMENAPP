// TrustProvenanceBadge.swift
// AMENAPP
//
// Wave 4 — the user-facing provenance label (human / AI-assisted / AI-generated)
// with an optional expandable edit history. Renders a TrustProvenanceLabel derived
// by ProvenanceLabelMapper from the real creation-time provenance record.
//
// Honest by construction: it shows only what the real label carries. It never
// claims "human" for AI-touched content.
//
// Gated by AMENFeatureFlags.shared.provenanceLabelsEnabled (default OFF).

import SwiftUI

struct TrustProvenanceBadge: View {
    let label: TrustProvenanceLabel
    /// Compact = chip only (feed); expanded-capable = tappable history (composer/detail).
    var allowsHistory: Bool = true

    @State private var showHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: showHistory ? 8 : 0) {
            chip
            if showHistory && !label.editHistory.isEmpty {
                historyList
            }
        }
    }

    private var chip: some View {
        Button {
            if allowsHistory && !label.editHistory.isEmpty { showHistory.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: label.origin.symbol)
                    .font(.caption2)
                Text(label.origin.displayName)
                    .font(.caption2.weight(.semibold))
                if allowsHistory && !label.editHistory.isEmpty {
                    Image(systemName: showHistory ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tint)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .tint(.blue) // affordance, when history is available
        .accessibilityLabel("Content origin: \(label.origin.displayName)")
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("EDIT HISTORY")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
            ForEach(Array(label.editHistory.enumerated()), id: \.offset) { _, edit in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: edit.actor == .ai ? "sparkles" : "person")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(edit.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}

// MARK: - Origin display (additive on the frozen Wave 0 contract)

extension ProvenanceOrigin {
    var displayName: String {
        switch self {
        case .human:       return "Made by a person"
        case .aiAssisted:  return "AI-assisted"
        case .aiGenerated: return "AI-generated"
        }
    }
    var symbol: String {
        switch self {
        case .human:       return "person.fill"
        case .aiAssisted:  return "wand.and.stars"
        case .aiGenerated: return "sparkles"
        }
    }
}

// MARK: - Attach modifier

extension View {
    /// Renders a provenance badge under the content when the flag is enabled.
    @ViewBuilder
    func provenanceLabel(_ label: TrustProvenanceLabel?, allowsHistory: Bool = true) -> some View {
        if AMENFeatureFlags.shared.provenanceLabelsEnabled, let label {
            VStack(alignment: .leading, spacing: 6) {
                self
                TrustProvenanceBadge(label: label, allowsHistory: allowsHistory)
            }
        } else {
            self
        }
    }
}

#if DEBUG
#Preview("Provenance — AI-assisted") {
    TrustProvenanceBadge(label: TrustProvenanceLabel(
        contentId: "post-1",
        origin: .aiAssisted,
        editHistory: [
            ProvenanceEdit(actor: .human, at: "2026-06-22T08:00:00Z", summary: "Written by author"),
            ProvenanceEdit(actor: .ai, at: "2026-06-22T08:01:00Z", summary: "ai_assisted_captions: caption suggestion")
        ]
    ))
    .padding()
}
#endif
