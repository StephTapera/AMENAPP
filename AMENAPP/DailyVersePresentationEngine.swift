// DailyVersePresentationEngine.swift
// Smart Header Orchestrator — Verse presentation style logic

import SwiftUI

// MARK: - Verse Presentation Style

enum VersePresentationStyle {
    case banner      // Full-height expandable banner (existing component)
    case inline      // Single-line reference + first few words
    case hidden      // Don't show verse in top chrome
}

// MARK: - Engine

struct DailyVersePresentationEngine {

    /// Decide how (or whether) to present the verse given current context.
    static func style(context: HeaderContext) -> VersePresentationStyle {
        guard context.hasVerseReady else { return .hidden }

        switch context.scrollOffset {
        case let o where o > 60:  return .hidden
        default: break
        }

        switch context.intentMode {
        case .pray, .reflect: return .banner
        case .create:         return .hidden
        default: break
        }

        switch context.timeOfDay {
        case .earlyMorning, .morning: return .banner
        case .evening, .night:        return .banner
        case .afternoon:              return .inline
        }
    }

    /// Accent color for the verse chrome given intent / time of day.
    static func accentColor(context: HeaderContext) -> Color {
        if let intent = context.intentMode {
            switch intent {
            case .pray:    return .purple
            case .reflect: return .indigo
            case .learn:   return .blue
            case .connect: return .teal
            case .create:  return .orange
            }
        }
        switch context.timeOfDay {
        case .earlyMorning: return .orange
        case .morning:      return .teal
        case .afternoon:    return .blue
        case .evening:      return .indigo
        case .night:        return .purple
        }
    }
}
