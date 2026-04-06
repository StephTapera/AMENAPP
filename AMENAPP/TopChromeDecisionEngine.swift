// TopChromeDecisionEngine.swift
// Smart Header Orchestrator — Pure decision logic (no UI, no side effects)

import Foundation

// MARK: - Variant

enum TopChromeVariant {
    case greetingOnly           // Just the greeting bar
    case verseOnly              // Just the verse banner (existing)
    case greetingAndVerse       // Greeting above verse
    case compact(String)        // Single-line merged: "Good morning · {verse preview}"
    case hidden                 // No chrome at all
}

// MARK: - Decision Engine

struct TopChromeDecisionEngine {

    /// Pure function — given context, returns the correct variant to display.
    static func decide(context: HeaderContext) -> TopChromeVariant {
        guard TopChromeFeatureFlags.smartHeaderEnabled else {
            // Feature off → pass-through to existing verse banner behaviour
            return .verseOnly
        }

        // Screens that opt out of the orchestrator
        guard context.screenType.allowsTopChrome else { return .hidden }

        // If user has scrolled far enough, collapse or hide
        if context.scrollOffset > 120 { return .hidden }
        if context.scrollOffset > 60  { return compactVariant(context: context) }

        // Intent-specific overrides
        if let intent = context.intentMode {
            switch intent {
            case .pray:    return .greetingOnly   // Reverent — no distractions
            case .create:  return .greetingOnly   // Focus — minimal chrome
            case .reflect: return fullOrCompact(context: context)
            default:       break
            }
        }

        // First launch today → full greeting + verse if both available
        if context.isFirstLaunchToday && context.hasVerseReady {
            return TopChromeFeatureFlags.verseFirstOrder ? .greetingAndVerse : .greetingAndVerse
        }

        // Verse already shown today → just greeting (verse below fold)
        if context.verseAlreadyShownToday {
            return .greetingOnly
        }

        // Verse available + not shown → show both
        if context.hasVerseReady {
            return .greetingAndVerse
        }

        // Fallback: greeting only
        return .greetingOnly
    }

    // MARK: - Helpers

    private static func fullOrCompact(context: HeaderContext) -> TopChromeVariant {
        context.hasVerseReady ? .greetingAndVerse : .greetingOnly
    }

    private static func compactVariant(context: HeaderContext) -> TopChromeVariant {
        let greeting = GreetingPresentationEngine.shortGreeting(
            timeOfDay: context.timeOfDay,
            name: context.userName
        )
        return .compact(greeting)
    }
}

// MARK: - ScreenType Extension

extension ScreenType {
    var allowsTopChrome: Bool {
        switch self {
        case .feed, .church, .resources: return true
        default: return false
        }
    }
}
