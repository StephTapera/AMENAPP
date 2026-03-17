//
//  BereanGreetingManager.swift
//  AMENAPP
//
//  Time-of-day aware greeting logic for the Berean AI landing screen.
//

import Foundation

/// Provides time-aware, curated greeting + follow-up pairs for the Berean landing screen.
struct BereanGreeting {
    let greeting: String    // e.g. "Good morning."
    let followUp: String    // e.g. "What wisdom are you seeking?"
}

enum BereanGreetingManager {

    // MARK: - Time Buckets

    enum TimePeriod {
        case morning    // 05:00 – 11:59
        case afternoon  // 12:00 – 16:59
        case evening    // 17:00 – 21:59
        case lateNight  // 22:00 – 04:59
    }

    static func currentPeriod(for date: Date = Date()) -> TimePeriod {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12:  return .morning
        case 12..<17: return .afternoon
        case 17..<22: return .evening
        default:      return .lateNight
        }
    }

    // MARK: - Curated Greeting Pairs

    /// Returns a curated, non-random greeting appropriate for the current time.
    /// Follow-ups rotate slowly by day-of-week to feel alive but not jarring.
    static func greeting(for date: Date = Date()) -> BereanGreeting {
        let period = currentPeriod(for: date)
        let dayOfWeek = Calendar.current.component(.weekday, from: date) // 1 (Sun) – 7 (Sat)

        switch period {
        case .morning:
            let followUps = [
                "How can I help today?",
                "What wisdom are you seeking?",
                "What would you like to understand?",
                "How may I serve you today?",
                "What are you carrying today?",
                "What are you seeking today?",
                "Where would you like to start?"
            ]
            return BereanGreeting(
                greeting: "Good morning.",
                followUp: followUps[(dayOfWeek - 1) % followUps.count]
            )

        case .afternoon:
            let followUps = [
                "What would you like to understand?",
                "How can I help today?",
                "What wisdom are you seeking?",
                "How may I serve you today?",
                "What are you working through?",
                "What's on your mind today?",
                "What are you seeking today?"
            ]
            return BereanGreeting(
                greeting: "Good afternoon.",
                followUp: followUps[(dayOfWeek - 1) % followUps.count]
            )

        case .evening:
            let followUps = [
                "What wisdom are you seeking?",
                "What would you like to understand?",
                "How may I serve you tonight?",
                "What are you reflecting on?",
                "How can I help tonight?",
                "What's on your heart tonight?",
                "What are you carrying tonight?"
            ]
            return BereanGreeting(
                greeting: "Good evening.",
                followUp: followUps[(dayOfWeek - 1) % followUps.count]
            )

        case .lateNight:
            let followUps = [
                "Let's think through it together.",
                "What's on your mind?",
                "How may I serve you?",
                "What wisdom are you seeking?",
                "What are you working through?",
                "Let's find some clarity.",
                "What are you carrying tonight?"
            ]
            return BereanGreeting(
                greeting: "Still up?",
                followUp: followUps[(dayOfWeek - 1) % followUps.count]
            )
        }
    }

    // MARK: - Subtitle

    static let subtitle = "Biblical wisdom for life, work, and understanding."
}
