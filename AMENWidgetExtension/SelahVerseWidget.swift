//
//  SelahVerseWidget.swift
//  AMENWidgetExtension
//
//  Reads the latest verse payload written by SelahLockScreenWidgetPublisher
//  in the main app via App Group UserDefaults.
//
//  Data flow:
//    Host app  →  UserDefaults(suiteName: "group.com.amenapp.shared")
//             →  key "selah.lockScreen.payload.v1"  (JSON-encoded SelahPayload)
//    Widget    ←  reads same key on timeline refresh
//
//  No Firebase, no network calls. This file compiles only in the widget
//  extension target process.
//

import WidgetKit
import SwiftUI

// MARK: - Shared payload model (mirrors SelahLockScreenWidgetPayload in host)

/// Local mirror of the host-app's `SelahLockScreenWidgetPayload`.
/// Fields must remain in sync with that struct's `CodingKeys`.
private struct SelahPayload: Codable {
    let headline: String
    let reference: String
    let snippet: String
    let translationAbbreviation: String
    let updatedAt: Date

    static let placeholder = SelahPayload(
        headline: "Daily verse",
        reference: "Psalm 23:1",
        snippet: "The LORD is my shepherd; I shall not want.",
        translationAbbreviation: "KJV",
        updatedAt: Date()
    )
}

// MARK: - TimelineEntry

struct SelahVerseEntry: TimelineEntry {
    let date: Date
    /// Display text for the verse body.
    let verseText: String
    /// Display reference, e.g. "Romans 5:3–5".
    let reference: String
    /// Translation abbreviation, e.g. "KJV".
    let translation: String
    /// Short header line, e.g. "Continue reading" or "Daily verse".
    let headline: String

    static let placeholder = SelahVerseEntry(
        date: Date(),
        verseText: "The LORD is my shepherd; I shall not want.",
        reference: "Psalm 23:1",
        translation: "KJV",
        headline: "Daily verse"
    )
}

// MARK: - TimelineProvider

struct SelahVerseProvider: TimelineProvider {

    private static let appGroupSuite = "group.com.amenapp.shared"
    private static let payloadKey    = "selah.lockScreen.payload.v1"

    // Use a date-only decoder so the ISO-8601 encoded Date from JSONEncoder
    // round-trips correctly.
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    private func loadPayload() -> SelahPayload? {
        guard
            let defaults = UserDefaults(suiteName: Self.appGroupSuite),
            let data     = defaults.data(forKey: Self.payloadKey)
        else { return nil }
        return try? decoder.decode(SelahPayload.self, from: data)
    }

    private func entry(from payload: SelahPayload?, date: Date) -> SelahVerseEntry {
        let p = payload ?? .placeholder
        return SelahVerseEntry(
            date: date,
            verseText: p.snippet,
            reference: p.reference,
            translation: p.translationAbbreviation,
            headline: p.headline
        )
    }

    // MARK: TimelineProvider conformance

    func placeholder(in context: Context) -> SelahVerseEntry {
        .placeholder
    }

    func getSnapshot(in context: Context,
                     completion: @escaping (SelahVerseEntry) -> Void) {
        completion(entry(from: loadPayload(), date: Date()))
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<SelahVerseEntry>) -> Void) {
        let now    = Date()
        let entry  = entry(from: loadPayload(), date: now)

        // Refresh at 6 AM the following morning so the verse updates overnight.
        var components        = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour       = 6
        components.minute     = 0
        components.second     = 0
        let nextMorning       = Calendar.current.nextDate(
            after:     now,
            matching:  components,
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(3600)

        completion(Timeline(entries: [entry], policy: .after(nextMorning)))
    }
}

// MARK: - Views

/// Small / medium widget view.
struct SelahVerseWidgetView: View {
    let entry: SelahVerseEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack {
            // Liquid-glass-style background using system material.
            ContainerRelativeShape()
                .fill(.regularMaterial)

            contentView
                .padding(family == .systemSmall ? 12 : 16)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var contentView: some View {
        switch family {
        case .systemSmall:
            smallContent
        case .systemMedium:
            mediumContent
        case .accessoryRectangular:
            accessoryRectangularContent
        case .accessoryInline:
            Text("\(entry.reference) · \(entry.translation)")
                .font(.caption2)
        default:
            smallContent
        }
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(entry.headline, systemImage: "book.closed.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 2)

            Text(entry.verseText)
                .font(.caption)
                .fontWeight(.regular)
                .foregroundStyle(.primary)
                .lineLimit(4)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 2)

            HStack(spacing: 4) {
                Text(entry.reference)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text("· \(entry.translation)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var mediumContent: some View {
        HStack(alignment: .top, spacing: 12) {
            // Leading icon column
            Image(systemName: "book.closed.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.headline)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(entry.verseText)
                    .font(.subheadline)
                    .fontWeight(.regular)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)

                Text("\(entry.reference)  \(entry.translation)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessoryRectangularContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.verseText)
                .font(.caption2)
                .lineLimit(2)
            Text(entry.reference)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }
}

/// Shown when the host app has never written a payload.
private struct SelahVerseEmptyView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "book.closed")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Open AMEN for your daily verse")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget

struct SelahVerseWidget: Widget {
    let kind = "SelahVerseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SelahVerseProvider()) { entry in
            // Show empty state when there's no real data yet.
            if entry.verseText == SelahVerseEntry.placeholder.verseText
                && entry.reference == SelahVerseEntry.placeholder.reference {
                SelahVerseWidgetView(entry: entry)
            } else {
                SelahVerseWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Daily Verse")
        .description("Your morning scripture from Selah")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Small", as: .systemSmall) {
    SelahVerseWidget()
} timeline: {
    SelahVerseEntry.placeholder
    SelahVerseEntry(
        date: Date(),
        verseText: "For God so loved the world that he gave his one and only Son.",
        reference: "John 3:16",
        translation: "NIV",
        headline: "Daily verse"
    )
}

#Preview("Medium", as: .systemMedium) {
    SelahVerseWidget()
} timeline: {
    SelahVerseEntry.placeholder
}

#Preview("Accessory Rectangular", as: .accessoryRectangular) {
    SelahVerseWidget()
} timeline: {
    SelahVerseEntry.placeholder
}
#endif
