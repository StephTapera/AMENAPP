//
//  AMENWidgetExtension.swift
//  AMENWidgetExtension
//
//  Home screen widgets for AMEN: Daily Verse, Prayer Count, Quick Actions.
//

import WidgetKit
import SwiftUI

// MARK: - Daily Verse Widget

struct DailyVerseProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyVerseEntry {
        DailyVerseEntry(
            date: Date(),
            reference: "Romans 8:28",
            text: "And we know that in all things God works for the good of those who love him.",
            theme: "Trust"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyVerseEntry) -> Void) {
        completion(loadCachedVerse())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyVerseEntry>) -> Void) {
        let entry = loadCachedVerse()
        // Refresh at midnight
        let midnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
        let timeline = Timeline(entries: [entry], policy: .after(midnight))
        completion(timeline)
    }

    private func loadCachedVerse() -> DailyVerseEntry {
        let defaults = UserDefaults(suiteName: "group.com.amenapp.shared")
        let reference = defaults?.string(forKey: "widgetVerseReference") ?? "Jeremiah 29:11"
        let text = defaults?.string(forKey: "widgetVerseText")
            ?? "\"For I know the plans I have for you,\" declares the LORD."
        let theme = defaults?.string(forKey: "widgetVerseTheme") ?? "Hope"

        return DailyVerseEntry(date: Date(), reference: reference, text: text, theme: theme)
    }
}

struct DailyVerseEntry: TimelineEntry {
    let date: Date
    let reference: String
    let text: String
    let theme: String
}

struct DailyVerseWidgetView: View {
    var entry: DailyVerseEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.12, blue: 0.18), Color(red: 0.06, green: 0.06, blue: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 10) {
                HStack {
                    Image(systemName: "book.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Daily Verse")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                }

                Text(entry.text)
                    .font(.system(size: family == .systemSmall ? 13 : 15, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(family == .systemSmall ? 3 : 4)
                    .lineSpacing(2)

                Spacer(minLength: 0)

                Text("— \(entry.reference)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(family == .systemSmall ? 14 : 16)
        }
        .widgetURL(URL(string: "amen://verse/today"))
    }
}

struct DailyVerseWidget: Widget {
    let kind: String = "DailyVerseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyVerseProvider()) { entry in
            DailyVerseWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Daily Verse")
        .description("Start your day with Scripture.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Prayer Count Widget

struct PrayerCountProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerCountEntry {
        PrayerCountEntry(date: Date(), prayerCount: 12, prayedForCount: 48)
    }

    func getSnapshot(in context: Context, completion: @escaping (PrayerCountEntry) -> Void) {
        completion(loadCachedCounts())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerCountEntry>) -> Void) {
        let entry = loadCachedCounts()
        let nextUpdate = Date().addingTimeInterval(900) // Refresh every 15 min
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadCachedCounts() -> PrayerCountEntry {
        let defaults = UserDefaults(suiteName: "group.com.amenapp.shared")
        return PrayerCountEntry(
            date: Date(),
            prayerCount: defaults?.integer(forKey: "widgetPrayerCount") ?? 0,
            prayedForCount: defaults?.integer(forKey: "widgetPrayedForCount") ?? 0
        )
    }
}

struct PrayerCountEntry: TimelineEntry {
    let date: Date
    let prayerCount: Int
    let prayedForCount: Int
}

struct PrayerCountWidgetView: View {
    var entry: PrayerCountEntry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.15, green: 0.10, blue: 0.22), Color(red: 0.08, green: 0.05, blue: 0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                Image(systemName: "hands.sparkles.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.8))

                VStack(spacing: 4) {
                    Text("\(entry.prayerCount)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Prayers")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

                if entry.prayedForCount > 0 {
                    Text("\(entry.prayedForCount) prayed for you")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding()
        }
        .widgetURL(URL(string: "amen://prayer"))
    }
}

struct PrayerCountWidget: Widget {
    let kind: String = "PrayerCountWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrayerCountProvider()) { entry in
            PrayerCountWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Prayer Counter")
        .description("See your prayer activity at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Quick Actions Widget

struct QuickActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickActionsEntry {
        QuickActionsEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickActionsEntry) -> Void) {
        completion(QuickActionsEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickActionsEntry>) -> Void) {
        let timeline = Timeline(entries: [QuickActionsEntry(date: Date())], policy: .never)
        completion(timeline)
    }
}

struct QuickActionsEntry: TimelineEntry {
    let date: Date
}

struct QuickActionsWidgetView: View {
    var entry: QuickActionsEntry

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.10)

            VStack(spacing: 12) {
                Text("AMEN")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.4))

                HStack(spacing: 16) {
                    quickAction(icon: "plus", label: "Post", url: "amen://compose")
                    quickAction(icon: "hands.sparkles.fill", label: "Pray", url: "amen://prayer")
                    quickAction(icon: "sparkles", label: "Berean", url: "amen://berean")
                    quickAction(icon: "magnifyingglass", label: "Search", url: "amen://discover")
                }
            }
            .padding()
        }
    }

    private func quickAction(icon: String, label: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08), in: Circle())

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

struct QuickActionsWidget: Widget {
    let kind: String = "QuickActionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickActionsProvider()) { entry in
            QuickActionsWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Quick Actions")
        .description("Post, pray, or ask Berean with one tap.")
        .supportedFamilies([.systemMedium])
    }
}
