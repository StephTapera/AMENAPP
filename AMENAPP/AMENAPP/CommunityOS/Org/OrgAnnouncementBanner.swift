// OrgAnnouncementBanner.swift
// AMEN Community OS — Org OS (A9)
//
// Card for org-level announcements.
// White card, left accent stripe (3pt, accentColor), expandable body.
//
// Design rules (C3): system colors only, Color.accentColor for interactive,
// no amenGold/amenPurple/hex colors.

import SwiftUI

// MARK: - OrgAnnouncementBanner

struct OrgAnnouncementBanner: View {

    let title: String
    let announcementBody: String
    let authorName: String
    let postedAt: Date

    /// Called when the user taps the expand / read-more affordance.
    var onExpand: (() -> Void)?

    // MARK: State

    @State private var isExpanded = false

    // MARK: Formatted date

    private var postedDateString: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: postedAt, relativeTo: Date())
    }

    // MARK: Body

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left accent stripe
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                // Title + metadata row
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .label))
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 4) {
                        Text(authorName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        Text(postedDateString)
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                }

                // Body (truncated unless expanded)
                Text(announcementBody)
                    .font(.callout)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .lineLimit(isExpanded ? nil : 3)
                    .multilineTextAlignment(.leading)
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)

                // Read more / Show less
                if needsExpansion {
                    Button {
                        if let action = onExpand, !isExpanded {
                            action()
                        }
                        withAnimation(.spring(response: 0.3)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Text(isExpanded ? "Show less" : "Read more")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Show less announcement" : "Read full announcement")
                }
            }
            .padding(.leading, 12)
            .padding(.vertical, 12)
            .padding(.trailing, 16)
        }
        .padding(.leading, 16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.07), radius: 24, x: 0, y: 5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). Announcement by \(authorName), \(postedDateString). \(announcementBody)")
    }

    // Heuristic: only show expand affordance if body is likely >3 lines
    private var needsExpansion: Bool {
        announcementBody.count > 120
    }
}

// MARK: - Preview

#Preview("Org Announcement Banner") {
    VStack(spacing: 16) {
        OrgAnnouncementBanner(
            title: "Upcoming Community Day – June 15",
            announcementBody: "Join us on June 15 for our annual Community Day celebration! We'll have food, worship, family activities, and opportunities to connect with others in the congregation. Doors open at 10am. All are welcome. Please bring a dish to share if you're able.",
            authorName: "Pastor Thompson",
            postedAt: Date(timeIntervalSinceNow: -3600 * 2),
            onExpand: nil
        )

        OrgAnnouncementBanner(
            title: "Volunteer Sign-Ups Open",
            announcementBody: "Short announcement text.",
            authorName: "Ministry Team",
            postedAt: Date(timeIntervalSinceNow: -3600 * 24),
            onExpand: nil
        )
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
