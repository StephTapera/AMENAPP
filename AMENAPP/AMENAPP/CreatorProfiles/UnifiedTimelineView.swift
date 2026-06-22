// UnifiedTimelineView.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3 UI
//
// One calm, CalmCap-paced stream interleaving the creator's events, teachings, resources,
// prayer updates, and courses. The inputs are the assembled payload's FIRST pages — this view
// renders a bounded slice and ends with an explicit terminus. NO infinite scroll.
//
// Exact initializer (mandated):
//   UnifiedTimelineView(events:teachings:resources:prayer:courses:)
//
// Conventions: white bg / black text; translucent glass cards on plain background (no
// glass-on-glass); AmenTheme.Colors.* tokens; Dynamic Type; VoiceOver labels; reduce-motion safe.

import SwiftUI

struct UnifiedTimelineView: View {
    let events: [CreatorHubEvent]
    let teachings: [CreatorHubTeaching]
    let resources: [CreatorHubResource]
    let prayer: [CreatorHubPrayerRequest]
    let courses: [CreatorHubCourse]

    /// Max items rendered in this bounded stream (CalmCap-aligned; default mirrors v1 cap).
    var maxItems: Int = CalmCap.v1Default.maxItemsPerShelf

    init(
        events: [CreatorHubEvent],
        teachings: [CreatorHubTeaching],
        resources: [CreatorHubResource],
        prayer: [CreatorHubPrayerRequest],
        courses: [CreatorHubCourse]
    ) {
        self.events = events
        self.teachings = teachings
        self.resources = resources
        self.prayer = prayer
        self.courses = courses
    }

    // MARK: Interleaved, bounded item model

    private enum TimelineItem: Identifiable {
        case event(CreatorHubEvent)
        case teaching(CreatorHubTeaching)
        case resource(CreatorHubResource)
        case prayer(CreatorHubPrayerRequest)
        case course(CreatorHubCourse)

        var id: String {
            switch self {
            case .event(let e):    return "event:\(e.id)"
            case .teaching(let t): return "teaching:\(t.id)"
            case .resource(let r): return "resource:\(r.id)"
            case .prayer(let p):   return "prayer:\(p.id)"
            case .course(let c):   return "course:\(c.id)"
            }
        }
    }

    /// Round-robin interleave so no single category dominates, then bound to maxItems.
    private var items: [TimelineItem] {
        var lanes: [[TimelineItem]] = [
            events.map(TimelineItem.event),
            teachings.map(TimelineItem.teaching),
            resources.map(TimelineItem.resource),
            // Public prayer updates only — never surface pending/private here.
            prayer.filter { $0.status == .approved && !$0.isPrivate }.map(TimelineItem.prayer),
            courses.map(TimelineItem.course),
        ]
        var merged: [TimelineItem] = []
        var laneIndex = 0
        while merged.count < maxItems && lanes.contains(where: { !$0.isEmpty }) {
            if !lanes[laneIndex].isEmpty {
                merged.append(lanes[laneIndex].removeFirst())
            }
            laneIndex = (laneIndex + 1) % lanes.count
        }
        return merged
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            header

            if items.isEmpty {
                emptyState
            } else {
                ForEach(items) { item in
                    card(for: item)
                }
                terminus
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header

    private var header: some View {
        Text("Latest")
            .font(.title3.weight(.semibold))
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Cards

    @ViewBuilder
    private func card(for item: TimelineItem) -> some View {
        switch item {
        case .event(let e):    timelineCard(icon: "calendar", kind: "Event", title: e.title, detail: eventDetail(e))
        case .teaching(let t): timelineCard(icon: "play.rectangle", kind: "Teaching", title: t.title, detail: t.series)
        case .resource(let r): timelineCard(icon: "doc.text", kind: "Resource", title: r.title, detail: r.topics.first)
        case .prayer(let p):   timelineCard(icon: "hands.and.sparkles", kind: "Prayer", title: p.body, detail: "\(p.prayedCount) praying")
        case .course(let c):   timelineCard(icon: "graduationcap", kind: "Course", title: c.title, detail: "\(c.modules.count) modules")
        }
    }

    private func timelineCard(icon: String, kind: String, title: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceChip)
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(kind.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                    .tracking(0.5)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .amenGlassCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind). \(title). \(detail ?? "")")
    }

    private func eventDetail(_ event: CreatorHubEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.startsAt)
    }

    // MARK: Terminus / empty

    private var terminus: some View {
        Text("That's everything for now.")
            .font(.footnote)
            .foregroundStyle(AmenTheme.Colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
            .accessibilityLabel("That's everything for now.")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(AmenTheme.Colors.iconSecondary)
            Text("Nothing here yet")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nothing here yet")
    }
}

#if DEBUG
#Preview("UnifiedTimelineView") {
    ScrollView {
        UnifiedTimelineView(
            events: [],
            teachings: [
                CreatorHubTeaching(id: "t1", creatorId: "demo", title: "Grace Unmerited",
                                   video: nil, audio: nil, transcriptRef: nil, notes: nil,
                                   outline: [], scriptureRefs: ["Eph 2:8"], topics: ["Grace"],
                                   series: "Foundations", speakers: [], aiSummaryRef: nil,
                                   durationSec: 1800)
            ],
            resources: [
                CreatorHubResource(id: "r1", creatorId: "demo", kind: .devotional,
                                   title: "7-Day Devotional", fileRef: nil,
                                   externalUrl: "https://example.com", topics: ["Hope"])
            ],
            prayer: [],
            courses: []
        )
    }
    .background(AmenTheme.Colors.backgroundPrimary)
}
#endif
