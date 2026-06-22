// TruthfulAILabels.swift
// AMEN App — Epistemic status labels for AI-generated content
//
// Marks content with a small badge indicating its epistemic status.
// Gated by truthfulAILabelsEnabled feature flag.

import SwiftUI

// MARK: - Main label view

struct TruthfulAILabel: View {
    enum EpistemicStatus {
        case verified
        case uncertain
        case speculative
        case synthetic
        case humanGenerated

        var systemImage: String {
            switch self {
            case .verified:       return "checkmark.seal.fill"
            case .uncertain:      return "questionmark.circle"
            case .speculative:    return "waveform.path.ecg"
            case .synthetic:      return "sparkles"
            case .humanGenerated: return "person.fill.checkmark"
            }
        }

        var labelText: String {
            switch self {
            case .verified:       return "Verified"
            case .uncertain:      return "Uncertain"
            case .speculative:    return "Speculative"
            case .synthetic:      return "AI-Generated"
            case .humanGenerated: return "Human"
            }
        }

        var color: Color {
            switch self {
            case .verified:       return .green
            case .uncertain:      return .orange
            case .speculative:    return .yellow
            case .synthetic:      return .blue
            case .humanGenerated: return .primary
            }
        }
    }

    let status: EpistemicStatus
    var compact: Bool = true

    @ObservedObject private var flags = AMENFeatureFlags.shared

    var body: some View {
        if !flags.truthfulAILabelsEnabled {
            EmptyView()
        } else if compact {
            compactPill
        } else {
            expandedChip
        }
    }

    // MARK: - Compact pill (22 pt tall capsule)

    private var compactPill: some View {
        Image(systemName: status.systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(status.color)
            .frame(width: 22, height: 22)
            .background(
                Capsule()
                    .fill(status.color.opacity(0.12))
                    .overlay(
                        Capsule()
                            .strokeBorder(status.color.opacity(0.28), lineWidth: 0.6)
                    )
            )
            .accessibilityLabel(status.labelText)
    }

    // MARK: - Expanded chip (icon + text)

    private var expandedChip: some View {
        HStack(spacing: 5) {
            Image(systemName: status.systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(status.labelText)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(status.color.opacity(0.10))
                .overlay(
                    Capsule()
                        .strokeBorder(status.color.opacity(0.24), lineWidth: 0.6)
                )
        )
        .accessibilityLabel(status.labelText)
    }
}

// MARK: - View extension

extension View {
    /// Overlays a `TruthfulAILabel` badge on the view.
    /// When the flag is off the view is returned unmodified.
    @ViewBuilder
    func truthfulAILabel(
        _ status: TruthfulAILabel.EpistemicStatus,
        compact: Bool = true
    ) -> some View {
        overlay(alignment: .topTrailing) {
            TruthfulAILabel(status: status, compact: compact)
                .padding(4)
        }
    }
}
