//
//  PrayerSessionLiveActivity.swift
//  AMENWidgetExtension
//
//  Dynamic Island + Lock Screen UI for the Prayer Session Live Activity.
//  Local-only (no push): the timer ticks automatically via Text(.timer).
//
//  Dynamic Island:
//    compactLeading  — 🙏 glyph
//    compactTrailing — elapsed timer
//    minimal         — 🙏 glyph
//    expanded        — title + timer + optional topic + End button (iOS 17+)
//
//  Lock Screen:
//    🙏 + title + elapsed timer + optional topic
//    widgetURL("amen://prayer/active") provides the iOS 16 tap fallback.
//

import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

// Gold accent matching Color.amenGold (AMENAPP/AmenTheme.swift) — kept inline
// so this file compiles without AmenTheme.swift in the widget target.
private let amenGold = Color(red: 0.83, green: 0.69, blue: 0.22)

struct PrayerSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerSessionAttributes.self) { context in
            PrayerSessionLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("🙏")
                        .font(.system(size: 22))
                        .padding(.leading, 4)
                        .accessibilityHidden(true)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(context.attributes.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(context.attributes.startedAt, style: .timer)
                            .font(.system(size: 15, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    .padding(.trailing, 4)
                    .accessibilityLabel("Timer: \(context.attributes.title)")
                }

                DynamicIslandExpandedRegion(.bottom) {
                    PrayerSessionExpandedBottomView(context: context)
                }
            } compactLeading: {
                Text("🙏")
                    .font(.system(size: 14))
                    .accessibilityLabel("Prayer session active")

            } compactTrailing: {
                Text(context.attributes.startedAt, style: .timer)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(minWidth: 38, alignment: .trailing)
                    .accessibilityLabel("Elapsed prayer time")

            } minimal: {
                Text("🙏")
                    .font(.system(size: 13))
                    .accessibilityLabel("Prayer session")
            }
        }
    }
}

// MARK: - Lock Screen / Banner

private struct PrayerSessionLockScreenView: View {
    let context: ActivityViewContext<PrayerSessionAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Text("🙏")
                .font(.system(size: 30))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(context.attributes.startedAt, style: .timer)
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)

                if let topic = context.state.topic {
                    Text(topic)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .activityBackgroundTint(amenGold.opacity(0.14))
        .activitySystemActionForegroundColor(.primary)
        // iOS 16 tap fallback — opens the app to the Prayer section.
        .widgetURL(URL(string: "amen://prayer/active"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Prayer session: \(context.attributes.title)."
            + (context.state.topic.map { " Topic: \($0)." } ?? "")
        )
    }
}

// MARK: - Expanded Bottom (title + topic + End button)

private struct PrayerSessionExpandedBottomView: View {
    let context: ActivityViewContext<PrayerSessionAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.attributes.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let topic = context.state.topic {
                Text(topic)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Spacer()
                if #available(iOSApplicationExtension 17.0, *) {
                    Button(intent: EndPrayerSessionIntent()) {
                        Label("End", systemImage: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(amenGold))
                    .accessibilityLabel("End prayer session")
                } else {
                    // iOS 16 fallback — tap the widget to open the app.
                    Link(destination: URL(string: "amen://prayer/active")!) {
                        Label("Open", systemImage: "arrow.up.right.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(amenGold))
                    }
                    .accessibilityLabel("Open prayer session in app")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}
