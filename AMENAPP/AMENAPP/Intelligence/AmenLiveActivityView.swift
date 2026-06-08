// AmenLiveActivityView.swift
// AMENAPP
//
// Live Activity UI for the Amen Living Intelligence system.
// Implements ALL three Dynamic Island surface sizes + Lock Screen banner.
//
// TARGET MEMBERSHIP: AMENWidgetExtension (NOT the main AMENAPP target).
// See AmenLiveActivityContractNotes.swift for the manual Xcode wiring steps.
//
// Formation rules enforced:
//   - NO spectacle counters (no "N people praying", no counts of any kind)
//   - Finite display: staleDate = card.expiresAt (set in AmenLiveActivityManager)
//   - Phase labels are status words, not metrics
//   - Tapping any surface deep-links into the main app

import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
import ActivityKit

// MARK: - Widget Entry Point

/// The `Widget` that registers the Amen Live Activity with WidgetKit / ActivityKit.
///
/// Add this to `AMENWidgetExtension`'s `@main` WidgetBundle:
/// ```swift
/// @main
/// struct AmenWidgetBundle: WidgetBundle {
///     var body: some Widget {
///         // existing widgets...
///         AmenLiveActivityWidget()
///     }
/// }
/// ```
@available(iOS 16.2, *)
struct AmenLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AmenLiveActivityAttributes.self) { context in
            // Lock Screen banner & StandBy mode
            AmenLiveActivityBannerView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island (user long-presses)
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

/// Displayed on the Lock Screen, in StandBy mode, and as a notification banner.
/// Finite: no scroll, no counts, no persistent engagement metrics.
@available(iOS 16.2, *)
struct AmenLiveActivityBannerView: View {
    let context: ActivityViewContext<AmenLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            // Tier icon — identity anchor for what kind of card this is
            tierIconView
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )

            // Title + subtitle stack
            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.title)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(context.state.subtitle)
                    .font(.systemScaled(13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Phase indicator — a status word, never a count
            phaseTagView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
        // Deep-link into the app on tap — action label guides intent
        .widgetURL(
            URL(string: "amenapp://intelligence/card/\(context.attributes.intelligenceCardId)")
        )
        // Accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel(bannerAccessibilityLabel)
        .accessibilityHint("Double-tap to \(context.state.actionLabel.lowercased()) in AMEN")
    }

    // MARK: Tier Icon

    @ViewBuilder
    private var tierIconView: some View {
        Image(systemName: context.attributes.tier.symbolName)
            .font(.systemScaled(16, weight: .medium))
            .foregroundStyle(tierColor)
            .accessibilityLabel(context.attributes.tier.accessibilityLabel)
    }

    // MARK: Phase Tag

    @ViewBuilder
    private var phaseTagView: some View {
        HStack(spacing: 4) {
            Image(systemName: context.state.phase.symbolName)
                .font(.systemScaled(10, weight: .semibold))
            Text(context.state.phase.displayLabel)
                .font(.systemScaled(11, weight: .medium))
        }
        .foregroundStyle(phaseColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(phaseColor.opacity(0.15))
        )
        .accessibilityLabel("Status: \(context.state.phase.displayLabel)")
    }

    // MARK: Helpers

    private var tierColor: Color {
        switch context.attributes.tier {
        case .spiritual:  return Color(red: 0.4, green: 0.3, blue: 0.85)
        case .community:  return Color(red: 0.2, green: 0.55, blue: 0.9)
        case .local:      return Color(red: 0.15, green: 0.7, blue: 0.5)
        case .global:     return Color(red: 0.85, green: 0.45, blue: 0.2)
        }
    }

    private var phaseColor: Color {
        Color(
            red: context.state.phase.tintRed,
            green: context.state.phase.tintGreen,
            blue: context.state.phase.tintBlue
        )
    }

    private var bannerAccessibilityLabel: String {
        "\(context.attributes.tier.accessibilityLabel) update: \(context.state.title). \(context.state.subtitle). \(context.state.phase.displayLabel)."
    }
}

// MARK: - Dynamic Island: Expanded Leading

/// Left region of expanded Dynamic Island.
/// Shows tier icon + tier name — the "what is this" anchor.
@available(iOS 16.2, *)
struct AmenLiveExpandedLeadingView: View {
    let context: ActivityViewContext<AmenLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: context.attributes.tier.symbolName)
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(tierColor)
            Text(context.attributes.tier.accessibilityLabel)
                .font(.systemScaled(12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
        .accessibilityElement(children: .combine)
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

// MARK: - Dynamic Island: Expanded Trailing

/// Right region of expanded Dynamic Island.
/// Shows phase indicator — a status word, never a count.
@available(iOS 16.2, *)
struct AmenLiveExpandedTrailingView: View {
    let context: ActivityViewContext<AmenLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: context.state.phase.symbolName)
                .font(.systemScaled(11, weight: .semibold))
                .foregroundStyle(phaseColor)
            Text(context.state.phase.displayLabel)
                .font(.systemScaled(11, weight: .medium))
                .foregroundStyle(phaseColor)
        }
        .padding(.trailing, 4)
        .accessibilityLabel("Status: \(context.state.phase.displayLabel)")
    }

    private var phaseColor: Color {
        Color(
            red: context.state.phase.tintRed,
            green: context.state.phase.tintGreen,
            blue: context.state.phase.tintBlue
        )
    }
}

// MARK: - Dynamic Island: Expanded Bottom

/// Bottom region of expanded Dynamic Island.
/// Shows title, subtitle, and action label deep-link.
/// NO spectacle counters. NO engagement metrics.
@available(iOS 16.2, *)
struct AmenLiveExpandedBottomView: View {
    let context: ActivityViewContext<AmenLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(context.state.title)
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(context.state.subtitle)
                .font(.systemScaled(12, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // CTA row — deep-links into the main app
            HStack {
                Spacer()
                Link(destination: URL(string: "amenapp://intelligence/card/\(context.attributes.intelligenceCardId)")!) {
                    Text(context.state.actionLabel)
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.4, green: 0.3, blue: 0.85))
                        )
                }
                .accessibilityLabel(context.state.actionLabel)
                .accessibilityHint("Opens in AMEN app")
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}

// MARK: - Dynamic Island: Compact Leading

/// Compact leading view — shown when another app has a compact trailing activity.
/// Displays the tier icon only — maximum information density for minimum space.
@available(iOS 16.2, *)
struct AmenLiveCompactLeadingView: View {
    let context: ActivityViewContext<AmenLiveActivityAttributes>

    var body: some View {
        Image(systemName: context.attributes.tier.symbolName)
            .font(.systemScaled(13, weight: .semibold))
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

// MARK: - Dynamic Island: Compact Trailing

/// Compact trailing view — shown when this app owns the compact trailing slot.
/// Displays phase indicator — a status symbol + label, never a count.
@available(iOS 16.2, *)
struct AmenLiveCompactTrailingView: View {
    let context: ActivityViewContext<AmenLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: context.state.phase.symbolName)
                .font(.systemScaled(10, weight: .bold))
                .foregroundStyle(phaseColor)
            Text(context.state.phase.displayLabel)
                .font(.systemScaled(10, weight: .semibold))
                .foregroundStyle(phaseColor)
                .lineLimit(1)
        }
        .accessibilityLabel("Status: \(context.state.phase.displayLabel)")
    }

    private var phaseColor: Color {
        Color(
            red: context.state.phase.tintRed,
            green: context.state.phase.tintGreen,
            blue: context.state.phase.tintBlue
        )
    }
}

// MARK: - Dynamic Island: Minimal

/// Minimal view — shown when two apps share the Dynamic Island pill.
/// Displays the tier icon ONLY. Single glyph, maximum restraint.
@available(iOS 16.2, *)
struct AmenLiveMinimalView: View {
    let context: ActivityViewContext<AmenLiveActivityAttributes>

    var body: some View {
        Image(systemName: context.attributes.tier.symbolName)
            .font(.systemScaled(12, weight: .semibold))
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
