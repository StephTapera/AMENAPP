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

// MARK: - AMEN Stats Widget (verse + unread counts)

struct AMENStatsEntry: TimelineEntry {
    let date: Date
    let verseText: String
    let verseRef: String
    let notifUnread: Int
    let messageUnread: Int
    let totalUnread: Int

    static let placeholder = AMENStatsEntry(
        date: .now,
        verseText: "Be still, and know that I am God.",
        verseRef: "Psalm 46:10",
        notifUnread: 3,
        messageUnread: 2,
        totalUnread: 5
    )
}

struct AMENStatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> AMENStatsEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (AMENStatsEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AMENStatsEntry>) -> Void) {
        let entry = load()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func load() -> AMENStatsEntry {
        let d = UserDefaults(suiteName: "group.com.amenapp.shared")
        return AMENStatsEntry(
            date: .now,
            verseText: d?.string(forKey: "widgetVerseText") ?? "Be still, and know that I am God.",
            verseRef: d?.string(forKey: "widgetVerseReference") ?? "Psalm 46:10",
            notifUnread: d?.integer(forKey: "widget_notif_unread") ?? 0,
            messageUnread: d?.integer(forKey: "widget_message_unread") ?? 0,
            totalUnread: d?.integer(forKey: "widget_unread") ?? 0
        )
    }
}

// Medium: verse left, stats right
struct AMENStatsMediumView: View {
    let entry: AMENStatsEntry

    private let bg = Color(red: 0.96, green: 0.94, blue: 0.91)
    private let ink = Color(red: 0.09, green: 0.07, blue: 0.05)
    private let red = Color(red: 0.75, green: 0.16, blue: 0.12)

    var body: some View {
        HStack(spacing: 0) {
            // Left — verse
            VStack(alignment: .leading, spacing: 6) {
                Text("AMEN")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(ink.opacity(0.3))
                    .kerning(1)
                Spacer()
                Text("\u{201C}\(entry.verseText)\u{201D}")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundStyle(ink.opacity(0.85))
                    .lineLimit(4)
                Text(entry.verseRef)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.4))
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Divider
            Rectangle()
                .fill(ink.opacity(0.08))
                .frame(width: 0.5)

            // Right — stats
            VStack(spacing: 12) {
                statCell(icon: "bell.fill", count: entry.notifUnread,
                         color: red, link: "amen://notifications")
                statCell(icon: "bubble.left.fill", count: entry.messageUnread,
                         color: Color(red: 0.15, green: 0.35, blue: 0.82), link: "amen://messages")
            }
            .frame(width: 80)
            .padding(.vertical, 14)
        }
        .background(bg)
        .widgetURL(URL(string: "amen://home"))
    }

    private func statCell(icon: String, count: Int, color: Color, link: String) -> some View {
        Link(destination: URL(string: link)!) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(color)
                        )
                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 6, y: -4)
                    }
                }
                Text(count > 99 ? "99+" : "\(count)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(ink)
                    .monospacedDigit()
            }
        }
    }
}

// Large: verse + stats row + quick actions
struct AMENStatsLargeView: View {
    let entry: AMENStatsEntry

    private let bg = Color(red: 0.96, green: 0.94, blue: 0.91)
    private let ink = Color(red: 0.09, green: 0.07, blue: 0.05)
    private let red = Color(red: 0.75, green: 0.16, blue: 0.12)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("AMEN")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(ink.opacity(0.3))
                    .kerning(1.2)
                Spacer()
                Text(entry.date, style: .date)
                    .font(.system(size: 9))
                    .foregroundStyle(ink.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Accent line
            Rectangle()
                .fill(red)
                .frame(width: 24, height: 2)
                .padding(.leading, 16)
                .padding(.bottom, 10)

            // Verse
            VStack(alignment: .leading, spacing: 4) {
                Text("\u{201C}\(entry.verseText)\u{201D}")
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(ink.opacity(0.85))
                    .lineLimit(3)
                Text("— \(entry.verseRef)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            // Divider
            Rectangle().fill(ink.opacity(0.07)).frame(height: 0.5)

            // Stats row
            HStack(spacing: 0) {
                largeStat(count: entry.notifUnread, label: "Notifications", link: "amen://notifications")
                Rectangle().fill(ink.opacity(0.07)).frame(width: 0.5, height: 30)
                largeStat(count: entry.messageUnread, label: "Messages", link: "amen://messages")
                Rectangle().fill(ink.opacity(0.07)).frame(width: 0.5, height: 30)
                largeStat(count: entry.totalUnread, label: "Total Unread", link: "amen://home")
            }
            .padding(.vertical, 14)

            // Divider
            Rectangle().fill(ink.opacity(0.07)).frame(height: 0.5)

            // Quick actions
            HStack(spacing: 8) {
                Link(destination: URL(string: "amen://compose")!) {
                    actionPill(label: "Post", icon: "plus.circle.fill", filled: true)
                }
                Link(destination: URL(string: "amen://prayer")!) {
                    actionPill(label: "Pray", icon: "hands.sparkles.fill", filled: false)
                }
                Link(destination: URL(string: "amen://berean")!) {
                    actionPill(label: "Berean", icon: "sparkles", filled: false)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(bg)
        .widgetURL(URL(string: "amen://home"))
    }

    private func largeStat(count: Int, label: String, link: String) -> some View {
        Link(destination: URL(string: link)!) {
            VStack(spacing: 2) {
                Text(count > 99 ? "99+" : "\(count)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(ink)
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(ink.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func actionPill(label: String, icon: String, filled: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 12))
            Text(label).font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(filled ? ink : ink.opacity(0.08)))
        .foregroundStyle(filled ? Color.white : ink)
    }
}

struct AMENStatsWidget: Widget {
    let kind = "AMENStatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AMENStatsProvider()) { entry in
            Group {
                if #available(iOSApplicationExtension 16.0, *) {
                    AMENStatsViewDispatcher(entry: entry)
                } else {
                    AMENStatsMediumView(entry: entry)
                }
            }
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("AMEN")
        .description("Daily verse, alerts, and quick actions.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@available(iOSApplicationExtension 16.0, *)
struct AMENStatsViewDispatcher: View {
    @Environment(\.widgetFamily) var family
    let entry: AMENStatsEntry
    var body: some View {
        switch family {
        case .systemLarge: AMENStatsLargeView(entry: entry)
        default: AMENStatsMediumView(entry: entry)
        }
    }
}

// MARK: - Lock Screen Widgets

@available(iOSApplicationExtension 16.0, *)
struct AMENLockScreenCircularView: View {
    let entry: AMENStatsEntry
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "cross.fill")
                    .font(.system(size: 10, weight: .semibold))
                if entry.totalUnread > 0 {
                    Text("\(min(entry.totalUnread, 99))")
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                }
            }
        }
        .widgetURL(URL(string: "amen://notifications"))
    }
}

@available(iOSApplicationExtension 16.0, *)
struct AMENLockScreenInlineView: View {
    let entry: AMENStatsEntry
    var body: some View {
        if entry.totalUnread > 0 {
            Label("\(entry.totalUnread) unread · \(entry.verseRef)", systemImage: "cross.fill")
        } else {
            Label(entry.verseRef, systemImage: "cross.fill")
        }
    }
}

@available(iOSApplicationExtension 16.0, *)
struct AMENLockScreenWidget: Widget {
    let kind = "AMENLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AMENStatsProvider()) { entry in
            AMENLockScreenDispatcher(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("AMEN Alerts")
        .description("Unread count at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

@available(iOSApplicationExtension 16.0, *)
struct AMENLockScreenDispatcher: View {
    @Environment(\.widgetFamily) var family
    let entry: AMENStatsEntry
    var body: some View {
        switch family {
        case .accessoryInline: AMENLockScreenInlineView(entry: entry)
        default: AMENLockScreenCircularView(entry: entry)
        }
    }
}
