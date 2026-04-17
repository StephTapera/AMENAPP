// ChurchJourneyTimelineView.swift
// AMENAPP
//
// Vertical timeline showing the user's journey with a specific church,
// from discovery through attendance and reflection.

import SwiftUI

struct ChurchJourneyTimelineView: View {
    let churchId: String
    let churchName: String

    @State private var milestones: [ChurchJourneyMilestone] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if milestones.isEmpty {
                emptyState
            } else {
                timelineContent
            }
        }
        .onAppear {
            milestones = ChurchJourneyTimelineService.shared.getFullTimeline(churchId: churchId)
        }
    }

    // MARK: - Timeline Content

    private var timelineContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("YOUR JOURNEY")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .kerning(1)
                Spacer()
                Text("\(milestones.count) milestones")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            // Milestone cards
            ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                HStack(alignment: .top, spacing: 12) {
                    // Timeline connector
                    VStack(spacing: 0) {
                        Circle()
                            .fill(accentColor(for: milestone))
                            .frame(width: 10, height: 10)

                        if index < milestones.count - 1 {
                            Rectangle()
                                .fill(Color(.systemGray4))
                                .frame(width: 1.5)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 10)
                    .padding(.top, 4)

                    // Milestone card
                    milestoneCard(milestone)
                        .padding(.bottom, index < milestones.count - 1 ? 12 : 0)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Milestone Card

    private func milestoneCard(_ milestone: ChurchJourneyMilestone) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: milestone.icon)
                    .font(.caption)
                    .foregroundStyle(accentColor(for: milestone))

                Text(milestone.phase.displayName.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accentColor(for: milestone))
                    .kerning(0.5)

                Spacer()

                Text(formattedDate(milestone.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(milestone.description)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.title2)
                .foregroundStyle(.tertiary)

            Text("No journey yet")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text("Your milestones with \(churchName) will appear here as you explore, plan, and visit.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Helpers

    private func accentColor(for milestone: ChurchJourneyMilestone) -> Color {
        switch milestone.accentColorName {
        case "blue":   return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "green":  return .green
        case "gold":   return Color(.sRGB, red: 0.96, green: 0.62, blue: 0.04, opacity: 1)
        case "teal":   return .teal
        default:       return .secondary
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
