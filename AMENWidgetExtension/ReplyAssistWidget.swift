//
//  ReplyAssistWidget.swift
//  AMENWidgetExtension
//
//  Home-screen widget that shows the number of conversations with pending
//  replies (unread DMs) and the name of the most recent one.
//
//  Data is written by the main app via:
//    UserDefaults(suiteName: "group.com.amenapp.shared")?
//        .set(count, forKey: "widget_pending_replies")
//    UserDefaults(suiteName: "group.com.amenapp.shared")?
//        .set(name,  forKey: "widget_top_conversation")
//    WidgetCenter.shared.reloadTimelines(ofKind: "ReplyAssistWidget")
//
//  No Firebase is imported here — widgets run in a sandboxed process and
//  must read only from the shared App Group UserDefaults container.
//

import WidgetKit
import SwiftUI

// MARK: - Constants

private let appGroupSuite = "group.com.amenapp.shared"
private let keyPendingReplies = "widget_pending_replies"
private let keyTopConversation = "widget_top_conversation"
private let deepLinkMessages = "amen://messages"

// MARK: - Timeline Entry

struct ReplyAssistEntry: TimelineEntry {
    let date: Date
    let pendingReplies: Int
    let topConversation: String

    static let placeholder = ReplyAssistEntry(
        date: .now,
        pendingReplies: 3,
        topConversation: "Sarah K."
    )

    static let empty = ReplyAssistEntry(
        date: .now,
        pendingReplies: 0,
        topConversation: ""
    )
}

// MARK: - Timeline Provider

struct ReplyAssistProvider: TimelineProvider {

    func placeholder(in context: Context) -> ReplyAssistEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ReplyAssistEntry) -> Void) {
        completion(context.isPreview ? .placeholder : loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReplyAssistEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh every 15 minutes in case the app hasn't signalled a reload.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }

    // MARK: Private

    private func loadEntry() -> ReplyAssistEntry {
        let defaults = UserDefaults(suiteName: appGroupSuite)
        let count = defaults?.integer(forKey: keyPendingReplies) ?? 0
        let top   = defaults?.string(forKey: keyTopConversation) ?? ""
        return ReplyAssistEntry(date: .now, pendingReplies: count, topConversation: top)
    }
}

// MARK: - Widget Views

struct ReplyAssistWidgetView: View {
    var entry: ReplyAssistEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryInline:
            inlineView
        default:
            smallView
        }
    }

    // MARK: systemSmall — pending count + top conversation name

    private var smallView: some View {
        ZStack {
            // Muted dark-blue-grey gradient consistent with the widget palette
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.12, blue: 0.20),
                    Color(red: 0.06, green: 0.07, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {

                // Header row
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                    Text("Messages")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                }

                Spacer(minLength: 0)

                // Count badge
                if entry.pendingReplies > 0 {
                    Text(entry.pendingReplies > 99 ? "99+" : "\(entry.pendingReplies)")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    Text(entry.pendingReplies == 1 ? "unread message" : "unread messages")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))

                    if !entry.topConversation.isEmpty {
                        Text("Latest: \(entry.topConversation)")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                            .padding(.top, 4)
                    }
                } else {
                    Image(systemName: "checkmark.bubble.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.bottom, 4)
                    Text("All caught up")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(14)
        }
        .widgetURL(URL(string: deepLinkMessages))
    }

    // MARK: accessoryCircular — unread count ring (Lock Screen / StandBy)

    @available(iOSApplicationExtension 16.0, *)
    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 11, weight: .semibold))
                if entry.pendingReplies > 0 {
                    Text(entry.pendingReplies > 99 ? "99+" : "\(entry.pendingReplies)")
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                }
            }
        }
        .widgetURL(URL(string: deepLinkMessages))
    }

    // MARK: accessoryInline — compact inline text (Lock Screen)

    private var inlineView: some View {
        Group {
            if entry.pendingReplies > 0 {
                Label(
                    "\(entry.pendingReplies) pending \(entry.pendingReplies == 1 ? "reply" : "replies")",
                    systemImage: "bubble.left.fill"
                )
            } else {
                Label("No unread messages", systemImage: "checkmark.bubble.fill")
            }
        }
        .widgetURL(URL(string: deepLinkMessages))
    }
}

// MARK: - Widget Declaration

struct ReplyAssistHomeWidget: Widget {
    /// Kind string used to target WidgetCenter.shared.reloadTimelines(ofKind:) calls.
    let kind: String = "ReplyAssistWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReplyAssistProvider()) { entry in
            ReplyAssistWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Messages")
        .description("See how many messages are waiting for your reply.")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        if #available(iOSApplicationExtension 16.0, *) {
            return [.systemSmall, .accessoryCircular, .accessoryInline]
        }
        return [.systemSmall]
    }
}

// MARK: - Previews

#Preview("Small — has replies", as: .systemSmall) {
    ReplyAssistHomeWidget()
} timeline: {
    ReplyAssistEntry(date: .now, pendingReplies: 5, topConversation: "Sarah K.")
}

#Preview("Small — empty state", as: .systemSmall) {
    ReplyAssistHomeWidget()
} timeline: {
    ReplyAssistEntry.empty
}
