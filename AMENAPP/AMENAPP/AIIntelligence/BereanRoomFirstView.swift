// BereanRoomFirstView.swift
// AMEN App — Room-first Berean response view for Spaces threads
//
// STRUCTURAL CONTRACT (enforced in view hierarchy):
// 1. "What the room said" section is rendered FIRST (humanSummary)
// 2. "Berean's perspective" section is rendered SECOND (bereanContribution)
// This order is not cosmetic — it reflects the architectural RoomSynthesis field order.
//
// Flag gate: AMENFeatureFlags.shared.bereanRoomFirst

import SwiftUI

// MARK: - BereanRoomFirstView

struct BereanRoomFirstView: View {

    let synthesis: RoomSynthesis

    var body: some View {
        guard AMENFeatureFlags.shared.bereanRoomFirst else {
            return AnyView(EmptyView())
        }
        return AnyView(content)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            // STRUCTURAL ORDER: humanSummary MUST appear before bereanContribution in the
            // view hierarchy. Do not reorder these two blocks.
            if synthesis.hasHumanSummary {
                humanSummarySection
            }
            bereanContributionSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Human Summary Section (rendered FIRST)

    private var humanSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("What the room said")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Text(synthesis.humanSummary)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        // Slightly warmer tint to distinguish human voices from AI
                        .fill(Color(.systemOrange).opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemOrange).opacity(0.15), lineWidth: 1)
                        )
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("What the room said: \(synthesis.humanSummary)")
    }

    // MARK: - Berean Contribution Section (rendered SECOND)

    private var bereanContributionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.accentColor)
                Text("Berean's perspective")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            if synthesis.bereanContribution.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                Text(synthesis.bereanContribution)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Berean's perspective: \(synthesis.bereanContribution)")
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    BereanRoomFirstView(
        synthesis: RoomSynthesis(
            humanSummary: "The room raised 3 perspectives. 1 question was raised.",
            bereanContribution: "Baptism in the New Testament signifies union with Christ in His death and resurrection (Romans 6:3-4)."
        )
    )
}
#endif
