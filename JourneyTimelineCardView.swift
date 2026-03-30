//
//  JourneyTimelineCardView.swift
//  AMENAPP
//
//  Full-width glass card for a single year-snapshot in the longitudinal timeline.
//  Colour-coded by emotionalColor field; left border matches the accent hue.
//

import SwiftUI

struct JourneyTimelineCardView: View {

    let snapshot: TopicSnapshot

    // MARK: - Computed accent colour

    private var accentColor: Color {
        switch snapshot.emotionalColor.lowercased() {
        case "gold":   return Color(.sRGB, red: 0.96, green: 0.62, blue: 0.04, opacity: 1)
        case "blue":   return .blue
        case "purple": return .purple
        case "green":  return .green
        default:       return .secondary
        }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {

            // ── Coloured left border bar ─────────────────────────────────
            LinearGradient(
                colors: [accentColor, accentColor.opacity(0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 3)
            .clipShape(
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            )
            .padding(.vertical, 4)
            .padding(.leading, 16)

            // ── Year + content ───────────────────────────────────────────
            HStack(alignment: .top, spacing: 16) {

                // Year number (tinted)
                Text(String(snapshot.year))
                    .font(AMENFont.bold(48))
                    .foregroundColor(accentColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .frame(width: 82, alignment: .leading)

                // Right-side content
                VStack(alignment: .leading, spacing: 8) {

                    // Chapter title
                    Text(snapshot.aiChapterTitle)
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    // Topic pills (first 3)
                    if !snapshot.topTopics.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(snapshot.topTopics.prefix(3), id: \.self) { topic in
                                TopicPillView(label: topic, color: accentColor)
                            }
                        }
                    }

                    // Scripture of the year
                    if let scripture = snapshot.scriptureOfYear {
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: "quote.opening")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .offset(y: 1)

                            Text(scripture)
                                .font(AMENFont.regular(12))
                                .italic()
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 4)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Topic Pill

private struct TopicPillView: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(AMENFont.medium(11))
            .foregroundColor(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
            .lineLimit(1)
    }
}

// MARK: - Preview

#if DEBUG
private let sampleSnapshot = TopicSnapshot(
    id: "1",
    year: 2023,
    topTopics: ["Faith", "Community", "Healing"],
    emotionalColor: "gold",
    aiChapterTitle: "Stepping Into the Open",
    topPostIds: [],
    scriptureOfYear: "Isaiah 43:19 – Behold, I am doing a new thing."
)

#Preview("Timeline Card") {
    VStack(spacing: 12) {
        JourneyTimelineCardView(snapshot: sampleSnapshot)
        JourneyTimelineCardView(snapshot: TopicSnapshot(
            id: "2", year: 2022, topTopics: ["Doubt", "Prayer"],
            emotionalColor: "purple",
            aiChapterTitle: "The Wilderness Season",
            topPostIds: [], scriptureOfYear: nil
        ))
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}
#endif
