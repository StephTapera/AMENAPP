import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

// MARK: - Lock Screen / Notification Banner

private struct PrayerLockScreenView: View {
    let context: ActivityViewContext<PrayerSessionAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text("🙏")
                .font(.system(size: 36))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(context.attributes.prayerTopic)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(
                    Date().addingTimeInterval(Double(-context.state.elapsedMinutes) * 60),
                    style: .timer
                )
                .font(.system(.title2, design: .rounded).monospacedDigit())
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .accessibilityLabel("Elapsed prayer time")

                if !context.state.prayerTitle.isEmpty {
                    Text(context.state.prayerTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }

            Spacer(minLength: 0)

            endControl
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .activityBackgroundTint(Color(red: 0.44, green: 0.26, blue: 0.80).opacity(0.88))
        .activitySystemActionForegroundColor(.white)
    }

    @ViewBuilder
    private var endControl: some View {
        if #available(iOS 17.0, *) {
            Button(intent: EndPrayerSessionIntent()) {
                Text("End")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End prayer session")
        } else {
            Link(destination: URL(string: "amenapp://prayer?action=end")!) {
                Text("End")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Dynamic Island — Expanded Bottom

private struct PrayerExpandedBottomView: View {
    let context: ActivityViewContext<PrayerSessionAttributes>

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if !context.state.prayerTitle.isEmpty {
                Text(context.state.prayerTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Praying…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(
                Date().addingTimeInterval(Double(-context.state.elapsedMinutes) * 60),
                style: .timer
            )
            .font(.system(.title3, design: .rounded).monospacedDigit())
            .fontWeight(.bold)
        }
        .padding(.top, 4)
    }
}

// MARK: - Widget Configuration

struct PrayerSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerSessionAttributes.self) { context in
            PrayerLockScreenView(context: context)
                .widgetURL(URL(string: "amenapp://prayer?action=timer"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Text("🙏")
                            .font(.title3)
                            .accessibilityHidden(true)
                        Text(context.attributes.prayerTopic)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if #available(iOS 17.0, *) {
                        Button(intent: EndPrayerSessionIntent()) {
                            Text("End")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.18))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 4)
                        .accessibilityLabel("End prayer session")
                    } else {
                        Link(destination: URL(string: "amenapp://prayer?action=end")!) {
                            Text("End")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.18))
                                .clipShape(Capsule())
                        }
                        .padding(.trailing, 4)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    PrayerExpandedBottomView(context: context)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                Text("🙏")
                    .font(.caption)
                    .accessibilityLabel("Prayer session active")
            } compactTrailing: {
                Text(
                    Date().addingTimeInterval(Double(-context.state.elapsedMinutes) * 60),
                    style: .timer
                )
                .font(.caption.monospacedDigit())
                .fontWeight(.semibold)
                .frame(minWidth: 38)
                .accessibilityLabel("Elapsed time")
            } minimal: {
                Text("🙏")
                    .accessibilityLabel("Prayer session active")
            }
            .widgetURL(URL(string: "amenapp://prayer?action=timer"))
            .keylineTint(Color(red: 0.44, green: 0.26, blue: 0.80))
        }
    }
}
