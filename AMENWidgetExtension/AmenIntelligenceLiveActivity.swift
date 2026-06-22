// AmenIntelligenceLiveActivity.swift
// AMENWidgetExtension
//
// Dynamic Island + Lock Screen UI for the Amen Living Intelligence Live Activity.
// Registered in AMENWidgetExtensionBundle as AmenLiveActivityWidget().
//
// Formation rules:
//   - NO spectacle counters (no "N people praying", no counts of any kind)
//   - Phase labels are status words only — never metrics
//   - Every tap deep-links into the main app

import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
import ActivityKit

// MARK: - Widget Entry Point

@available(iOS 16.2, *)
struct AmenLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AmenLiveActivityAttributes.self) { context in
            AmenLiveActivityBannerView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    AmenLiveExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AmenLiveExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    AmenLiveExpandedBottomView(context: context)
                }
            } compactLeading: {
                AmenLiveCompactLeadingView(context: context)
            } compactTrailing: {
                AmenLiveCompactTrailingView(context: context)
            } minimal: {
                AmenLiveMinimalView(context: context)
            }
        }
    }
}

// MARK: - Lock Screen Banner

@available(iOS 16.2, *)
struct AmenLiveActivityBannerView: View {
    let context: ActivityViewContext<AmenLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            tierIconView
                .frame(width: 36, height: 36)
                .background(Circle().fill(.ultraThinMaterial))

            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(context.state.subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            phaseTagView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
        .widgetURL(URL(string: "amenapp://intelligence/card/\(context.attributes.intelligenceCardId)"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(bannerAccessibilityLabel)
        .accessibilityHint("Double-tap to \(context.state.actionLabel.lowercased()) in AMEN")
    }

    @ViewBuilder
    private var tierIconView: some View {
        Image(systemName: context.attributes.tier.symbolName)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(tierColor)
            .accessibilityLabel(context.attributes.tier.accessibilityLabel)
    }

    @ViewBuilder
    private var phaseTagView: some View {
        HStack(spacing: 4) {
            Image(systemName: context.state.phase.symbolName)
                .font(.system(size: 10, weight: .semibold))
            Text(context.state.phase.displayLabel)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(phaseColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(phaseColor.opacity(0.15)))
        .accessibilityLabel("Status: \(context.state.phase.displayLabel)")
    }

    private var tierColor: Color {
        switch context.attributes.tier {
        case .spiritual:  return Color(red: 0.4, green: 0.3, blue: 0.85)
        case .community:  return Color(red: 0.2, green: 0.55, blue: 0.9)
        case .local:      return Color(red: 0.15, green: 0.7, blue: 0.5)
        case .global:     return Color(red: 0.85, green: 0.45, blue: 0.2)
        }
    }

    private var phaseColor: Color {
        Color(red: context.state.phase.tintRed, green: context.state.phase.tintGreen, blue: context.state.phase.tintBlue)
    }

    private var bannerAccessibilityLabel: String {
        "\(context.attributes.tier.accessibilityLabel) update: \(context.state.title). \(context.state.subtitle). \(context.state.phase.displayLabel)."
    }
}

// MARK: - Expanded Leading

@available(iOS 16.2, *)
struct AmenLiveExpandedLeadingView: View {
    let context: ActivityViewContext<AmenLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: context.attributes.tier.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tierColor)
            Text(context.attributes.tier.accessibilityLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
        .accessibilityLabel(context.attributes.tier.accessibilityLabel)
    }

    private var tierColor: Color {
        switch context.attributes.tier {
        case .spiritual:  return Color(red: 0.4, green: 0.3, blue: 0.85)
        case .community:  return Color(red: 0.2, green: 0.55, blue: 0.9)
        case .local:      return Color(red: 0.15, green: 0.7, blue: 0.5)
        case .global:     return Color(red: 0.85, green: 0.45, blue: 0.2)
        }
    }
}

// MARK: - Expanded Trailing

@available(iOS 16.2, *)
struct AmenLiveExpandedTrailingView: View {
    let context: ActivityViewContext<AmenLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: context.state.phase.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(phaseColor)
            Text(context.state.phase.displayLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(phaseColor)
        }
        .padding(.trailing, 4)
        .accessibilityLabel("Status: \(context.state.phase.displayLabel)")
    }

    private var phaseColor: Color {
        Color(red: context.state.phase.tintRed, green: context.state.phase.tintGreen, blue: context.state.phase.tintBlue)
    }
}

// MARK: - Expanded Bottom

@available(iOS 16.2, *)
struct AmenLiveExpandedBottomView: View {
    let context: ActivityViewContext<AmenLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(context.state.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(context.state.subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Spacer()
                Link(destination: URL(string: "amenapp://intelligence/card/\(context.attributes.intelligenceCardId)")!) {
                    Text(context.state.actionLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(red: 0.4, green: 0.3, blue: 0.85)))
                }
                .accessibilityLabel(context.state.actionLabel)
                .accessibilityHint("Opens in AMEN app")
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}

// MARK: - Compact Leading

@available(iOS 16.2, *)
struct AmenLiveCompactLeadingView: View {
    let context: ActivityViewContext<AmenLiveActivityAttributes>

    var body: some View {
        Image(systemName: context.attributes.tier.symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tierColor)
            .frame(width: 20, height: 20)
            .accessibilityLabel("AMEN \(context.attributes.tier.accessibilityLabel) update")
    }

    private var tierColor: Color {
        switch context.attributes.tier {
        case .spiritual:  return Color(red: 0.4, green: 0.3, blue: 0.85)
        case .community:  return Color(red: 0.2, green: 0.55, blue: 0.9)
        case .local:      return Color(red: 0.15, green: 0.7, blue: 0.5)
        case .global:     return Color(red: 0.85, green: 0.45, blue: 0.2)
        }
    }
}

// MARK: - Compact Trailing

@available(iOS 16.2, *)
struct AmenLiveCompactTrailingView: View {
    let context: ActivityViewContext<AmenLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: context.state.phase.symbolName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(phaseColor)
            Text(context.state.phase.displayLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(phaseColor)
                .lineLimit(1)
        }
        .accessibilityLabel("Status: \(context.state.phase.displayLabel)")
    }

    private var phaseColor: Color {
        Color(red: context.state.phase.tintRed, green: context.state.phase.tintGreen, blue: context.state.phase.tintBlue)
    }
}

// MARK: - Minimal

@available(iOS 16.2, *)
struct AmenLiveMinimalView: View {
    let context: ActivityViewContext<AmenLiveActivityAttributes>

    var body: some View {
        Image(systemName: context.attributes.tier.symbolName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tierColor)
            .accessibilityLabel("AMEN \(context.attributes.tier.accessibilityLabel)")
    }

    private var tierColor: Color {
        switch context.attributes.tier {
        case .spiritual:  return Color(red: 0.4, green: 0.3, blue: 0.85)
        case .community:  return Color(red: 0.2, green: 0.55, blue: 0.9)
        case .local:      return Color(red: 0.15, green: 0.7, blue: 0.5)
        case .global:     return Color(red: 0.85, green: 0.45, blue: 0.2)
        }
    }
}

#endif // canImport(ActivityKit)
