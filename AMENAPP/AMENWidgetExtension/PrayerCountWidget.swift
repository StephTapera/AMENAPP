//
//  PrayerCountWidget.swift
//  AMENWidgetExtension
//
//  Displays the number of prayers the user has sent today.
//
//  Data flow:
//    Host app  →  UserDefaults(suiteName: "group.com.amenapp.shared")
//             →  key "prayer_count_today"  (Int)
//    Widget    ←  reads same key, refreshes hourly
//
//  No Firebase, no network calls. This file compiles only in the widget
//  extension target process.
//

import WidgetKit
import SwiftUI

// MARK: - TimelineEntry

struct PrayerCountEntry: TimelineEntry {
    let date: Date
    /// Number of prayers sent today. Defaults to 0 if not yet written.
    let prayerCount: Int

    static let placeholder = PrayerCountEntry(date: Date(), prayerCount: 0)
}

// MARK: - TimelineProvider

struct PrayerCountProvider: TimelineProvider {

    private static let appGroupSuite = "group.com.amenapp.shared"
    private static let countKey      = "prayer_count_today"

    private func loadCount() -> Int {
        UserDefaults(suiteName: Self.appGroupSuite)?
            .integer(forKey: Self.countKey) ?? 0
    }

    // MARK: TimelineProvider conformance

    func placeholder(in context: Context) -> PrayerCountEntry {
        .placeholder
    }

    func getSnapshot(in context: Context,
                     completion: @escaping (PrayerCountEntry) -> Void) {
        completion(PrayerCountEntry(date: Date(), prayerCount: loadCount()))
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<PrayerCountEntry>) -> Void) {
        let now   = Date()
        var entries: [PrayerCountEntry] = []

        // Emit one entry per hour for the next 12 hours so the count stays
        // roughly current without hammering the system scheduler.
        for hour in 0..<12 {
            let entryDate = now.addingTimeInterval(TimeInterval(hour) * 3600)
            entries.append(PrayerCountEntry(date: entryDate, prayerCount: loadCount()))
        }

        // .atEnd tells WidgetKit to call getTimeline again after the last entry.
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Views

struct PrayerCountWidgetView: View {
    let entry: PrayerCountEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(.regularMaterial)

            contentView
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var contentView: some View {
        switch family {
        case .accessoryCircular:
            circularContent
        case .accessoryRectangular:
            rectangularContent
        case .systemSmall:
            smallContent
        default:
            smallContent
        }
    }

    // MARK: Accessory Circular (lock screen / watch face style)

    private var circularContent: some View {
        VStack(spacing: 2) {
            Image(systemName: "heart.fill")
                .font(.caption2)
                .foregroundStyle(.pink)
            Text("\(entry.prayerCount)")
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: Accessory Rectangular (lock screen banner)

    private var rectangularContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.caption)
                .foregroundStyle(.pink)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.prayerCount)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                + Text(" prayers")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("sent today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: System Small (home screen)

    private var smallContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.title2)
                .foregroundStyle(.pink)

            VStack(spacing: 2) {
                Text("\(entry.prayerCount)")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.6)

                Text("Prayers Today")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(12)
    }
}

// MARK: - Widget

struct PrayerCountWidget: Widget {
    let kind = "PrayerCountWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrayerCountProvider()) { entry in
            PrayerCountWidgetView(entry: entry)
        }
        .configurationDisplayName("Prayers Today")
        .description("How many prayers you've sent today")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .systemSmall
        ])
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Circular", as: .accessoryCircular) {
    PrayerCountWidget()
} timeline: {
    PrayerCountEntry(date: Date(), prayerCount: 7)
    PrayerCountEntry(date: Date(), prayerCount: 12)
}

#Preview("Small", as: .systemSmall) {
    PrayerCountWidget()
} timeline: {
    PrayerCountEntry(date: Date(), prayerCount: 7)
}

#Preview("Accessory Rectangular", as: .accessoryRectangular) {
    PrayerCountWidget()
} timeline: {
    PrayerCountEntry(date: Date(), prayerCount: 7)
}
#endif
