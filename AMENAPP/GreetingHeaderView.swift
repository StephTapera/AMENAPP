// GreetingHeaderView.swift
// Smart Header Orchestrator — Greeting component (white bg, black text, Liquid Glass)

import SwiftUI

struct GreetingHeaderView: View {
    let context: HeaderContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            // Greeting icon
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 38, height: 38)
                Image(systemName: timeIcon)
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(GreetingPresentationEngine.greeting(
                    timeOfDay: context.timeOfDay,
                    name: context.userName
                ))
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(Color(.label))

                Text(GreetingPresentationEngine.subtitle(
                    timeOfDay: context.timeOfDay,
                    intentMode: context.intentMode
                ))
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(Color(.secondaryLabel))
            }

            Spacer()

            // Intent mode pill (if set)
            if let intent = context.intentMode {
                IntentModePill(intent: intent)
            }
        }
        .padding(.horizontal, TopChromeMetrics.containerPadding)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private var timeIcon: String {
        switch context.timeOfDay {
        case .earlyMorning: return "sunrise.fill"
        case .morning:      return "sun.max.fill"
        case .afternoon:    return "sun.min.fill"
        case .evening:      return "sunset.fill"
        case .night:        return "moon.stars.fill"
        }
    }

    private var iconColor: Color {
        DailyVersePresentationEngine.accentColor(context: context)
    }

    private var iconBackground: Color {
        iconColor.opacity(0.12)
    }
}

// MARK: - Intent Mode Pill

private struct IntentModePill: View {
    let intent: FeedIntentMode

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: intent.icon)
                .font(.systemScaled(10, weight: .semibold))
            Text(intent.rawValue)
                .font(.custom("OpenSans-SemiBold", size: 11))
        }
        .foregroundStyle(Color(.secondaryLabel))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(.tertiarySystemFill))
                .overlay(
                    Capsule().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
                )
        )
    }
}
