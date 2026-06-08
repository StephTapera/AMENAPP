// EnhancedChurchCard.swift
// AMENAPP
//
// Enhanced church card components for the Find a Church experience.
// - ChurchMatchIndicator: compact score + top reason badge
// - WhyThisChurchHint: expandable recommendation reasons
// - ChurchVibeTagsRow: scrollable vibe/tag pills
// - ChurchCardExpandedContent: enriched expanded state with preparation + CTA stack

import SwiftUI

// MARK: - Church Match Indicator

/// Compact badge showing match percentage and top reason.
struct ChurchMatchIndicator: View {
    let score: Double  // 0–100
    let topReason: ChurchRecommendationReason?

    private var color: Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return Color(.secondaryLabel)
    }

    var body: some View {
        if score > 0 {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.systemScaled(9))
                Text("\(Int(score))%")
                    .font(.systemScaled(11, weight: .bold))
                if let reason = topReason {
                    Text("·")
                        .font(.systemScaled(9))
                    Text(reason.shortReason)
                        .font(.systemScaled(10))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .amenGlassEffect(in: Capsule())
        }
    }
}

// MARK: - Church Vibe Tags Row

/// Horizontal scroll of vibe/characteristic tag pills for a church.
struct ChurchVibeTagsRow: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.systemScaled(11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .amenGlassEffect(in: Capsule())
                    }
                }
            }
        }
    }
}

// MARK: - Why This Church Hint

/// Expandable "Why we recommend this" section showing recommendation reasons.
struct WhyThisChurchHint: View {
    let reasons: [ChurchRecommendationReason]
    @State private var isExpanded = false

    var body: some View {
        if !reasons.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.systemScaled(11))
                            .foregroundStyle(.orange)
                        Text("Why this church?")
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.systemScaled(10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(reasons.prefix(3)) { reason in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: reason.category.icon)
                                    .font(.systemScaled(11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reason.shortReason)
                                        .font(.systemScaled(12, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text(reason.longReason)
                                        .font(.systemScaled(11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .amenGlassEffect(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

// MARK: - Church Card Expanded Content

/// Enriched expanded state content for church cards.
/// Shows service times, preparation section, vibe tags, first-visit insights,
/// and CTA stack (Plan Visit, Create Note, Share).
struct ChurchCardExpandedContent: View {
    let church: Church
    let interaction: ChurchInteraction?
    let isPlanned: Bool
    var onPlanAttendance: () -> Void
    var onCreateNote: () -> Void
    var onShareExperience: () -> Void
    var onGetDirections: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let liveRed = Color(red: 0.878, green: 0.227, blue: 0.227)

    private var isServiceLive: Bool {
        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)
        let weekday = cal.component(.weekday, from: now)
        return weekday == 1 && hour >= 8 && hour < 13
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().padding(.horizontal, 2)

            // Service schedule chips
            VStack(alignment: .leading, spacing: 8) {
                Text("Service Times")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(serviceChips, id: \.self) { chip in
                            Text(chip)
                                .font(.systemScaled(12, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(isServiceLive ? liveRed : .primary)
                                .amenGlassEffect(in: Capsule())
                        }
                    }
                }
            }

            // Recommendation reasons
            if let interaction, !interaction.recommendationReasons.isEmpty {
                WhyThisChurchHint(reasons: interaction.recommendationReasons)
            }

            // Checklist progress (if planning)
            if let interaction, interaction.phase >= .planning {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Visit Preparation")
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(interaction.checklist.completedCount)/\(interaction.checklist.totalCount)")
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    ProgressView(value: interaction.checklist.completionPercentage)
                        .tint(.accentColor)
                }
            }

            // CTA stack
            VStack(spacing: 10) {
                // Get Directions
                Button(action: onGetDirections) {
                    Label("Get Directions", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor))
                }
                .buttonStyle(.plain)

                // Plan attendance
                Button(action: onPlanAttendance) {
                    Label(
                        isPlanned ? "Planning to Attend" : "Plan Visit",
                        systemImage: isPlanned ? "calendar.badge.checkmark" : "calendar.badge.plus"
                    )
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(isPlanned ? .green : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .amenGlassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                // Secondary CTAs
                HStack(spacing: 10) {
                    Button(action: onCreateNote) {
                        Label("Create Note", systemImage: "square.and.pencil")
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .amenGlassEffect(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: onShareExperience) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .amenGlassEffect(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }

    private var serviceChips: [String] {
        let base = church.serviceTime
        if base.isEmpty { return ["Sunday 10:00 AM"] }
        return base.components(separatedBy: CharacterSet(charactersIn: ",&"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
