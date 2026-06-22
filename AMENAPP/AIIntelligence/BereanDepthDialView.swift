// BereanDepthDialView.swift
// AMENAPP — Berean Spiritual Intelligence Layer (Wave 2)
//
// Canonical 5-stop depth selector used by both the IntentSwitchChip popover and
// the Long-Press depth dial. Single source of truth — do not duplicate.
//
// Shows depth label, token ceiling hint, latency hint, and an "Auto" badge
// beside the auto-selected stop.

import SwiftUI

struct BereanDepthDialView: View {

    let currentDepth: BereanDepth
    let autoDepth: BereanDepth
    let onSelect: (BereanDepth) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let feedbackGenerator = UISelectionFeedbackGenerator()

    var body: some View {
        ZStack {
            // Container background — opaque when reduce-transparency; glass otherwise
            if reduceTransparency {
                Color(.systemBackground)
            } else {
                Color(.systemBackground).opacity(0.0)
            }

            VStack(spacing: 4) {
                ForEach(BereanDepth.allCases) { depth in
                    DepthRow(
                        depth: depth,
                        isSelected: depth == currentDepth,
                        isAuto: depth == autoDepth,
                        reduceMotion: reduceMotion,
                        onTap: {
                            feedbackGenerator.selectionChanged()
                            onSelect(depth)
                        }
                    )
                }
            }
            .padding(12)
        }
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - DepthRow

private struct DepthRow: View {

    let depth: BereanDepth
    let isSelected: Bool
    let isAuto: Bool
    let reduceMotion: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Checkmark — space reserved always to keep rows aligned
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.blue)
                    .opacity(isSelected ? 1.0 : 0.0)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(depth.displayLabel)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .blue : Color(.label))

                        if isAuto {
                            Text("Auto")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue, in: Capsule())
                        }
                    }

                    Text("\(tokenCeilingLabel(depth)) · \(latencyLabel(depth))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.blue.opacity(0.08))
                }
            }
            .scaleEffect(isSelected && !reduceMotion ? 1.02 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75),
                       value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text("\(depth.displayLabel), \(tokenCeilingLabel(depth)), \(latencyLabel(depth))\(isAuto ? ", Auto selected" : "")")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Hint Labels

    private func tokenCeilingLabel(_ d: BereanDepth) -> String {
        let k = d.tokenCeiling / 1_000
        return "~\(k)k tokens"
    }

    private func latencyLabel(_ d: BereanDepth) -> String {
        let s = d.latencyBudgetMs / 1_000
        return "≤\(s)s"
    }
}
