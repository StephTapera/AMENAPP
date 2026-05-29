//
//  AmenDailyVerseWidget.swift
//  AmenWidgetExtension
//
// SETUP REQUIRED:
// 1. Add Widget Extension target in Xcode (File → New → Target → Widget Extension)
// 2. Add App Group capability: group.com.amen.app to BOTH main app AND widget extension
// 3. Add this file + AmenPrayerWidget.swift + AmenWidgetBundle.swift to Widget Extension target
// 4. Remove AmenWidgetBundle.swift from main app target (it has @main)
// 5. Call AmenWidgetData.saveVerse(verse) from main app when daily verse loads
//    Example: inside DailyVerseGenkitService after setting todayVerse, call:
//      AmenWidgetData.saveVerse(WidgetVerse(reference: verse.reference,
//                                           text: verse.text,
//                                           translation: "NIV",
//                                           date: verse.date))
//      AmenWidgetData.reloadWidgets()

import WidgetKit
import SwiftUI

// MARK: - Brand colors (defined locally — do not import AmenTheme which has UIKit deps)

private extension Color {
    /// widgetGold — canonical AMEN gold for widget surfaces (no AmenTheme UIKit dep)
    static let widgetGold   = Color(red: 0.855, green: 0.647, blue: 0.125)
    /// widgetPurple — deep plum from brand palette for widget surfaces
    static let widgetPurple = Color(red: 0.220, green: 0.098, blue: 0.196)
    /// Dark widget background (matches iOS dark #1C1C1E)
    static let widgetBackground = Color(red: 0.110, green: 0.110, blue: 0.118)
}

// MARK: - Fallback verse used when no App Group data is available

private let fallbackVerse = WidgetVerse(
    reference: "Romans 8:28",
    text: "And we know that in all things God works for the good of those who love him, who have been called according to his purpose.",
    translation: "NIV",
    date: Date()
)

// MARK: - Timeline Entry

struct DailyVerseEntry: TimelineEntry {
    let date: Date
    let verse: WidgetVerse?
}

// MARK: - Timeline Provider

struct DailyVerseProvider: TimelineProvider {

    // Placeholder shown in the widget gallery before real data loads
    func placeholder(in context: Context) -> DailyVerseEntry {
        DailyVerseEntry(date: Date(), verse: fallbackVerse)
    }

    // Snapshot shown in Xcode previews and quick look
    func getSnapshot(in context: Context, completion: @escaping (DailyVerseEntry) -> Void) {
        let verse = AmenWidgetData.loadVerse() ?? fallbackVerse
        completion(DailyVerseEntry(date: Date(), verse: verse))
    }

    // Full timeline: one entry per day, refreshed at midnight
    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyVerseEntry>) -> Void) {
        let verse = AmenWidgetData.loadVerse() ?? fallbackVerse
        let entry = DailyVerseEntry(date: Date(), verse: verse)

        // Refresh at the start of the next calendar day
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.day = (components.day ?? 0) + 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        let midnight = Calendar.current.date(from: components) ?? Date().addingTimeInterval(86400)

        let timeline = Timeline(entries: [entry], policy: .after(midnight))
        completion(timeline)
    }
}

// MARK: - Entry View

struct DailyVerseWidgetEntryView: View {
    var entry: DailyVerseEntry
    @Environment(\.widgetFamily) var family

    private var verse: WidgetVerse { entry.verse ?? fallbackVerse }

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        case .accessoryRectangular:
            accessoryRectangularView
        case .accessoryCircular:
            accessoryCircularView
        default:
            mediumView
        }
    }

    // MARK: - Small (2×2)

    private var smallView: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [.widgetBackground, Color.black],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                // AMEN logo text
                Text("AMEN")
                    .font(.system(size: 10, weight: .black, design: .default))
                    .foregroundStyle(Color.widgetGold)
                    .tracking(2.5)

                Spacer()

                // Cross decoration
                Image(systemName: "cross.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.widgetGold.opacity(0.5))

                // Verse reference
                Text(verse.reference)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                // First line of verse
                Text(verse.text)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    // MARK: - Medium (4×2)

    private var mediumView: some View {
        ZStack {
            LinearGradient(
                colors: [.widgetBackground, Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(spacing: 0) {
                // Gold accent bar
                Rectangle()
                    .fill(Color.widgetGold)
                    .frame(width: 3)
                    .padding(.vertical, 16)

                VStack(alignment: .leading, spacing: 6) {
                    // Verse reference
                    Text(verse.reference)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.widgetGold)
                        .lineLimit(1)

                    // Full verse text
                    Text(verse.text)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineSpacing(2)
                        .lineLimit(4)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 0)

                    // Translation label
                    Text(verse.translation)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.leading, 10)
                .padding(.trailing, 12)
                .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    // MARK: - Large (4×4)

    private var largeView: some View {
        ZStack {
            LinearGradient(
                colors: [.widgetBackground, Color.black],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Text("Daily Verse")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.widgetGold)
                        .tracking(0.5)
                    Spacer()
                    Image(systemName: "cross.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.widgetGold.opacity(0.6))
                }

                // Divider
                Rectangle()
                    .fill(Color.widgetGold.opacity(0.3))
                    .frame(height: 1)

                // Full verse text — large and readable
                Text("\"\(verse.text)\"")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(.white)
                    .lineSpacing(5)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                // Reference
                Text("— \(verse.reference)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.widgetGold)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Spacer(minLength: 0)

                // Deep-link CTA
                Link(destination: URL(string: "amen://verse")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Open AMEN")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.widgetGold.opacity(0.25))
                            .overlay(
                                Capsule().strokeBorder(Color.widgetGold.opacity(0.5), lineWidth: 1)
                            )
                    )
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    // MARK: - Lock Screen: Rectangular

    private var accessoryRectangularView: some View {
        HStack(spacing: 6) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 1) {
                Text(verse.reference)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                let preview = String(verse.text.prefix(60))
                Text(preview + (verse.text.count > 60 ? "..." : ""))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Lock Screen: Circular

    private var accessoryCircularView: some View {
        VStack(spacing: 2) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            // Day-of-month number as a simple spiritual counter
            let day = Calendar.current.component(.day, from: entry.date)
            Text("\(day)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Widget Declaration

struct DailyVerseWidget: Widget {
    let kind: String = "AmenDailyVerse"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyVerseProvider()) { entry in
            DailyVerseWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Daily Verse")
        .description("Your daily scripture from AMEN")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryRectangular,
            .accessoryCircular
        ])
        // .widgetURL is only available on WidgetConfiguration; removed for IntentConfiguration compatibility
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    DailyVerseWidget()
} timeline: {
    DailyVerseEntry(date: .now, verse: fallbackVerse)
}
