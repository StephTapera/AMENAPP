// VisitMemoryCard.swift
// Private visit memory summary card
// AMENAPP

import SwiftUI

// MARK: - VisitMemoryCard

struct VisitMemoryCard: View {

    let insights: ChurchVisitInsights
    let lastReflectionSnippet: String?
    let isSaved: Bool

    private var lastVisitLabel: String {
        guard let lastVisit = insights.lastVisitAt else { return "No visits yet" }
        let components = Calendar.current.dateComponents([.day, .weekOfYear, .month], from: lastVisit, to: Date())
        if let days = components.day, days == 0 {
            return "Last visited today"
        } else if let days = components.day, days == 1 {
            return "Last visited yesterday"
        } else if let days = components.day, days < 7 {
            return "Last visited \(days) days ago"
        } else if let weeks = components.weekOfYear, weeks == 1 {
            return "Last visited last week"
        } else if let weeks = components.weekOfYear, weeks < 4 {
            return "Last visited \(weeks) weeks ago"
        } else if let months = components.month, months == 1 {
            return "Last visited last month"
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Last visited " + formatter.localizedString(for: lastVisit, relativeTo: Date())
        }
    }

    private var favoriteServiceTime: String? {
        insights.commonServiceTimes.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack {
                Text("Your History")
                    .font(AMENFont.bold(15))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Visit count badge
            HStack(spacing: 8) {
                Text("\(insights.totalVisits) \(insights.totalVisits == 1 ? "visit" : "visits")")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(Color(red: 0.0, green: 0.5, blue: 0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.0, green: 0.5, blue: 0.5).opacity(0.12))
                    )

                if isSaved {
                    Text("Saved")
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.10))
                        )
                }
            }

            // Last visit date
            if insights.totalVisits > 0 {
                Label(lastVisitLabel, systemImage: "calendar")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)
            }

            // Last reflection snippet
            if let snippet = lastReflectionSnippet, !snippet.isEmpty {
                Text("\"\(snippet)\"")
                    .font(AMENFont.regular(13).italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Favorite service time
            if let serviceTime = favoriteServiceTime {
                Label("Usually attend \(serviceTime)", systemImage: "clock.fill")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        }
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VisitMemoryCard(
        insights: ChurchVisitInsights(
            totalVisits: 3,
            favoriteChurchIds: [],
            commonServiceTimes: ["Sunday mornings"],
            lastVisitedChurchId: "abc",
            lastVisitAt: Calendar.current.date(byAdding: .day, value: -14, to: Date()),
            topReflectionThemes: ["Faith", "Grace"]
        ),
        lastReflectionSnippet: "God's love is unconditional and I need to walk in that daily.",
        isSaved: true
    )
    .padding()
}
#endif
