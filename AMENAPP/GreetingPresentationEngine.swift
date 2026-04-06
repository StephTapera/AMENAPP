// GreetingPresentationEngine.swift
// Smart Header Orchestrator — Greeting copy generation

import Foundation

struct GreetingPresentationEngine {

    // MARK: - Full Greeting

    static func greeting(timeOfDay: TimeOfDay, name: String) -> String {
        let salutation = salutation(for: timeOfDay)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? salutation : "\(salutation), \(trimmed.components(separatedBy: " ").first ?? trimmed)"
    }

    // MARK: - Short Greeting (compact mode — no name)

    static func shortGreeting(timeOfDay: TimeOfDay, name: String) -> String {
        let salutation = salutation(for: timeOfDay)
        let first = name.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""
        return first.isEmpty ? salutation : "\(salutation), \(first)"
    }

    // MARK: - Subtitle

    static func subtitle(timeOfDay: TimeOfDay, intentMode: FeedIntentMode?) -> String {
        if let intent = intentMode {
            return intentSubtitle(intent)
        }
        return timeSubtitle(timeOfDay)
    }

    // MARK: - Private

    private static func salutation(for timeOfDay: TimeOfDay) -> String {
        switch timeOfDay {
        case .earlyMorning: return "Good morning"
        case .morning:      return "Good morning"
        case .afternoon:    return "Good afternoon"
        case .evening:      return "Good evening"
        case .night:        return "Good evening"
        }
    }

    private static func timeSubtitle(_ timeOfDay: TimeOfDay) -> String {
        switch timeOfDay {
        case .earlyMorning: return "Rise and shine"
        case .morning:      return "Start your day with faith"
        case .afternoon:    return "Midday moment with God"
        case .evening:      return "Wind down with the Word"
        case .night:        return "Rest in His peace"
        }
    }

    private static func intentSubtitle(_ intent: FeedIntentMode) -> String {
        switch intent {
        case .reflect:  return "Take a moment to be still"
        case .learn:    return "Grow in wisdom and truth"
        case .connect:  return "Encourage someone today"
        case .create:   return "Create with purpose"
        case .pray:     return "Bring it all to Him"
        }
    }
}
