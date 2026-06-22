//
//  PrayerRequestLiveActivity.swift
//  AMENWidgetExtension
//
//  Dynamic Island + Lock Screen UI for the push-driven Prayer Request activity.
//  Shows live prayingCount, an "✨ Testimony" state when isAnswered flips, and
//  an interactive "🙏 I'm praying" button (iOS 17+) / Link fallback (iOS 16).
//

import SwiftUI
import AppIntents
import WidgetKit
import ActivityKit

struct PrayerRequestLiveActivity: Widget {
    private let amenGold = Color(red: 0.83, green: 0.69, blue: 0.22)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerRequestAttributes.self) { context in
            PrayerRequestLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("🙏 Prayer")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(context.attributes.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isAnswered {
                        Text("✨")
                            .font(.system(size: 20))
                            .padding(.trailing, 8)
                    } else if #available(iOSApplicationExtension 17.0, *) {
                        Button(intent: PrayForRequestIntent(requestId: context.attributes.requestId)) {
                            Label("\(context.state.prayingCount)", systemImage: "hands.sparkles")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(amenGold)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    } else {
                        PrayingCountBadge(count: context.state.prayingCount, gold: amenGold)
                            .padding(.trailing, 8)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 16) {
                        if context.state.isAnswered {
                            Label("Testimony received!", systemImage: "sparkles")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(amenGold)
                        } else {
                            Label("\(context.state.prayingCount) praying", systemImage: "hands.sparkles.fill")
                                .font(.system(size: 12))
                            if context.state.encouragementCount > 0 {
                                Label("\(context.state.encouragementCount) encouraged", systemImage: "heart.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                Image(systemName: "hands.sparkles.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(amenGold)
            } compactTrailing: {
                Text("\(context.state.prayingCount)")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(amenGold)
            } minimal: {
                Image(systemName: "hands.sparkles.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(amenGold)
            }
            .widgetURL(URL(string: "amen://pray/\(context.attributes.requestId)"))
            .keylineTint(amenGold)
        }
    }
}

// MARK: - Lock Screen

private struct PrayerRequestLockScreenView: View {
    let context: ActivityViewContext<PrayerRequestAttributes>
    private let amenGold = Color(red: 0.83, green: 0.69, blue: 0.22)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(amenGold.opacity(0.18))
                    .frame(width: 44, height: 44)
                Text(context.state.isAnswered ? "✨" : "🙏")
                    .font(.system(size: 24))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if context.state.isAnswered {
                    Text("Testimony received!")
                        .font(.system(size: 12))
                        .foregroundStyle(amenGold)
                } else {
                    Text("\(context.state.prayingCount) praying now")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if context.state.isAnswered {
                Text("✨")
                    .font(.system(size: 24))
            } else if #available(iOSApplicationExtension 17.0, *) {
                Button(intent: PrayForRequestIntent(requestId: context.attributes.requestId)) {
                    Image(systemName: "hands.sparkles.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(amenGold)
                        .padding(9)
                        .background(Circle().fill(amenGold.opacity(0.14)))
                }
                .buttonStyle(.plain)
            } else {
                Link(destination: URL(string: "amen://pray/\(context.attributes.requestId)")!) {
                    Image(systemName: "hands.sparkles.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(amenGold)
                        .padding(9)
                        .background(Circle().fill(amenGold.opacity(0.14)))
                }
            }
        }
        .padding(14)
        .activityBackgroundTint(amenGold.opacity(0.14))
        .activitySystemActionForegroundColor(.primary)
        .widgetURL(URL(string: "amen://pray/\(context.attributes.requestId)"))
    }
}

// MARK: - Helper

private struct PrayingCountBadge: View {
    let count: Int
    let gold: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "hands.sparkles.fill").font(.system(size: 10))
            Text("\(count)").font(.system(size: 12, weight: .bold).monospacedDigit())
        }
        .foregroundStyle(gold)
    }
}
