//
//  AmenLiveActivityViews.swift
//  AMENAPP
//
//  Dynamic Island + Lock Screen rendering for all AMEN Live Activity types.
//
//  IMPORTANT — Widget Extension Target:
//  This file (and AmenLiveActivityAttributes.swift) must be added to the
//  AMENWidgetExtension target so Xcode can render them in the Dynamic Island.
//  The main app target only needs AmenLiveActivityManager.swift +
//  AmenLiveActivityAttributes.swift.
//
//  Design language:
//    • Dark background (.black.opacity(0.85)) — consistent with AMEN Liquid Glass at night
//    • Brand accent per activity type:
//        Prayer  → amenGold    (warmth, sacred)
//        Berean  → amenPurple  (wisdom, study)
//        Church  → amenBlue    (community, gathering)
//    • SF Symbols: filled weight for compact/minimal; regular for expanded body text
//    • No user-generated content in compact / minimal regions
//

#if canImport(ActivityKit)
import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

// ═════════════════════════════════════════════════════════════════════════════
// MARK: - Shared helpers
// ═════════════════════════════════════════════════════════════════════════════

/// Dark pill background used for the "LIVE" badge and streak counters.
@available(iOS 16.2, *)
private struct LivePill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }
}

/// A branded progress bar track + fill.
@available(iOS 16.2, *)
private struct AmenProgressBar: View {
    let progress: Double   // 0.0–1.0
    let fillColor: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 4)
                Capsule()
                    .fill(fillColor)
                    .frame(width: geo.size.width * max(0, min(1, progress)), height: 4)
            }
        }
        .frame(height: 4)
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// MARK: - Prayer Session Widget
// ═════════════════════════════════════════════════════════════════════════════

@available(iOS 16.2, *)
struct PrayerSessionWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerSessionAttributes.self) { context in
            // Lock Screen / StandBy banner
            PrayerLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // ── Expanded island ─────────────────────────────────────────
                DynamicIslandExpandedRegion(.leading) {
                    PrayerExpandedView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EmptyView()
                }
            } compactLeading: {
                // Flame icon in amenGold
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
            } compactTrailing: {
                // Elapsed time counter
                Text("\(context.state.elapsedMinutes)m")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            } minimal: {
                // Single flame when island is shared
                Image(systemName: "flame.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
            }
            .keylineTint(AmenTheme.Colors.amenGold.opacity(0.4))
            .contentMargins(.horizontal, 14, for: .expanded)
            .contentMargins(.top, 12, for: .expanded)
            .contentMargins(.bottom, 14, for: .expanded)
        }
    }
}

// MARK: Prayer — Expanded region view

@available(iOS 16.2, *)
private struct PrayerExpandedView: View {
    let context: ActivityViewContext<PrayerSessionAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                Text("Praying Together")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
            }

            Text(context.state.prayerTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)

            HStack(spacing: 10) {
                Label(
                    "\(context.state.participantCount) participants",
                    systemImage: "person.2.fill"
                )
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))

                if context.state.isChurchMode {
                    Label("Church", systemImage: "building.columns.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
    }
}

// MARK: Prayer — Lock Screen banner

@available(iOS 16.2, *)
private struct PrayerLockScreenView: View {
    let context: ActivityViewContext<PrayerSessionAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenGold)

            VStack(alignment: .leading, spacing: 2) {
                Text("Praying Together")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                Text(context.state.prayerTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(context.state.participantCount) participants · \(context.state.elapsedMinutes)m")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.85))
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// MARK: - Berean Study Widget
// ═════════════════════════════════════════════════════════════════════════════

@available(iOS 16.2, *)
struct BereanStudyWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BereanStudyAttributes.self) { context in
            BereanLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BereanExpandedView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EmptyView()
                }
            } compactLeading: {
                // Book icon in amenPurple
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
            } compactTrailing: {
                // Current position: "John 3:16"
                Text("\(context.state.currentBook) \(context.state.currentVerse)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
            }
            .keylineTint(AmenTheme.Colors.amenPurple.opacity(0.4))
            .contentMargins(.horizontal, 14, for: .expanded)
            .contentMargins(.top, 12, for: .expanded)
            .contentMargins(.bottom, 14, for: .expanded)
        }
    }
}

// MARK: Berean — Expanded region view

@available(iOS 16.2, *)
private struct BereanExpandedView: View {
    let context: ActivityViewContext<BereanStudyAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
                Text(context.attributes.studyPlanName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
                    .lineLimit(1)
            }

            Text("\(context.state.currentBook) \(context.state.currentVerse)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)

            // Progress bar
            AmenProgressBar(
                progress: context.state.progressPercent,
                fillColor: AmenTheme.Colors.amenPurple
            )

            // Streak badge
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                Text("\(context.state.streakDays) day streak")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }
}

// MARK: Berean — Lock Screen banner

@available(iOS 16.2, *)
private struct BereanLockScreenView: View {
    let context: ActivityViewContext<BereanStudyAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenPurple)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.studyPlanName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
                    .lineLimit(1)
                Text("\(context.state.currentBook) \(context.state.currentVerse)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)

                HStack(spacing: 6) {
                    AmenProgressBar(
                        progress: context.state.progressPercent,
                        fillColor: AmenTheme.Colors.amenPurple
                    )
                    .frame(width: 80)

                    Text("\(context.state.streakDays)d streak")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.85))
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// MARK: - Church Event Widget
// ═════════════════════════════════════════════════════════════════════════════

@available(iOS 16.2, *)
struct ChurchEventWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChurchEventAttributes.self) { context in
            ChurchEventLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ChurchEventExpandedView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EmptyView()
                }
            } compactLeading: {
                // Church icon in amenBlue
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
            } compactTrailing: {
                // "LIVE" or "in Xm" countdown
                if context.state.isLive {
                    LivePill(label: "LIVE", color: AmenTheme.Colors.amenBlue)
                } else {
                    Text("in \(context.state.minutesUntilStart)m")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            } minimal: {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
            }
            .keylineTint(AmenTheme.Colors.amenBlue.opacity(0.4))
            .contentMargins(.horizontal, 14, for: .expanded)
            .contentMargins(.top, 12, for: .expanded)
            .contentMargins(.bottom, 14, for: .expanded)
        }
    }
}

// MARK: Church Event — Expanded region view

@available(iOS 16.2, *)
private struct ChurchEventExpandedView: View {
    let context: ActivityViewContext<ChurchEventAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
                Text(context.attributes.churchName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
                    .lineLimit(1)
            }

            Text(context.state.serviceName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(context.attributes.address)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)

            // Live pill or countdown
            if context.state.isLive {
                LivePill(label: "Live Now", color: AmenTheme.Colors.amenBlue)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Starts in \(context.state.minutesUntilStart) min")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                        .monospacedDigit()
                }
            }
        }
    }
}

// MARK: Church Event — Lock Screen banner

@available(iOS 16.2, *)
private struct ChurchEventLockScreenView: View {
    let context: ActivityViewContext<ChurchEventAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.churchName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
                    .lineLimit(1)
                Text(context.state.serviceName)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(context.attributes.address)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer()

            // Status indicator
            if context.state.isLive {
                LivePill(label: "LIVE", color: AmenTheme.Colors.amenBlue)
            } else {
                VStack(spacing: 1) {
                    Text("in")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("\(context.state.minutesUntilStart)m")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.85))
    }
}

#endif // canImport(ActivityKit)
