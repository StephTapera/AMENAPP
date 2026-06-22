//
//  HeyFeedNLModels.swift
//  AMENAPP
//
//  Duration-aware feed preferences created from natural-language input.
//  These stack on top of HeyFeedPreferences for temporary, expiring controls.
//  Stored at users/{userId}/feedNLPreferences/{preferenceId}
//

import Foundation

// MARK: - Duration

enum HeyFeedDuration: String, Codable, CaseIterable, Sendable {
    case session      = "session"       // Current app session only
    case today        = "today"         // Expires at midnight
    case threeDays    = "three_days"    // 72 hours
    case sevenDays    = "seven_days"    // 7 days
    case persistent   = "persistent"   // Until manually removed

    var label: String {
        switch self {
        case .session:    return "this session"
        case .today:      return "today"
        case .threeDays:  return "3 days"
        case .sevenDays:  return "this week"
        case .persistent: return "ongoing"
        }
    }

    var expiryDate: Date? {
        let cal = Calendar.current
        switch self {
        case .session:
            return Date().addingTimeInterval(3 * 3600) // 3 hour session proxy
        case .today:
            return cal.startOfDay(for: Date()).addingTimeInterval(86400)
        case .threeDays:
            return Date().addingTimeInterval(3 * 86400)
        case .sevenDays:
            return Date().addingTimeInterval(7 * 86400)
        case .persistent:
            return nil
        }
    }

    var shortLabel: String {
        switch self {
        case .session:    return "now"
        case .today:      return "today"
        case .threeDays:  return "3d"
        case .sevenDays:  return "7d"
        case .persistent: return "∞"
        }
    }
}

// MARK: - Action

enum HeyFeedNLAction: String, Codable, Sendable {
    case increase  // more of this
    case decrease  // less of this
    case mute      // none of this
    case explore   // show me new things in this area
    case balance   // rebalance (reset)
}

// MARK: - Target

enum HeyFeedNLTargetType: String, Codable, Sendable {
    case topic
    case tone
    case creatorType
    case relationship  // "from people I follow"
    case locality      // "local churches"
    case format
    case novelty
    case intensity
}

struct HeyFeedNLTarget: Codable, Identifiable, Sendable {
    var id: String            // taxonomy ID e.g. "testimonies", "debate"
    var type: HeyFeedNLTargetType
    var label: String         // human-readable "Testimonies"
    var confidence: Double    // 0.0–1.0
}

// MARK: - Parsed Intent

struct HeyFeedParsedIntent: Codable, Sendable {
    let action: HeyFeedNLAction
    let targets: [HeyFeedNLTarget]
    let duration: HeyFeedDuration
    let strength: Double        // 0.0–1.0, default 0.7
    let confidence: Double      // overall parse confidence
    let originalText: String
    let requiresConfirmation: Bool   // true when confidence < 0.6
    let parserVersion: Int
}

// MARK: - Active NL Preference

struct HeyFeedNLPreference: Identifiable, Codable, Sendable {
    var id: String
    var action: HeyFeedNLAction
    var targetId: String
    var targetLabel: String
    var targetType: HeyFeedNLTargetType
    var strength: Double
    var duration: HeyFeedDuration
    var source: String          // "nl_input", "quick_chip", "session_mode"
    var isActive: Bool
    var isPaused: Bool
    var createdAt: Date
    var expiresAt: Date?        // nil = persistent

    var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        return Date() > exp
    }

    var timeRemainingLabel: String {
        guard let exp = expiresAt else { return duration.shortLabel }
        let remaining = exp.timeIntervalSinceNow
        if remaining <= 0 { return "expired" }
        if remaining < 3600  { return "\(Int(remaining/60))m" }
        if remaining < 86400 { return "\(Int(remaining/3600))h" }
        return "\(Int(remaining/86400))d"
    }

    /// Effective ranking delta to apply. Positive = boost, negative = demote.
    var rankingDelta: Double {
        guard isActive && !isPaused && !isExpired else { return 0 }
        let base: Double
        switch action {
        case .increase: base = strength * 0.35
        case .decrease: base = -(strength * 0.35)
        case .mute:     base = -1.0
        case .explore:  base = strength * 0.20
        case .balance:  base = 0
        }
        return base
    }
}

// MARK: - Session Mode

enum HeyFeedSessionMode: String, Codable, CaseIterable, Sendable {
    case none                       = "none"
    case lighterTonight             = "lighter_tonight"
    case moreEncouragement          = "more_encouragement"
    case moreBibleTeaching          = "more_bible_teaching"
    case lessControversy            = "less_controversy"
    case moreLocalChurches          = "more_local_churches"
    case exploreNewCreators         = "explore_new_creators"
    case morePrayerTestimonies      = "more_prayer_testimonies"
    case morePracticalFaith         = "more_practical_faith"

    var label: String {
        switch self {
        case .none:                  return "No session mode"
        case .lighterTonight:        return "Keep it lighter"
        case .moreEncouragement:     return "More encouragement"
        case .moreBibleTeaching:     return "More Bible teaching"
        case .lessControversy:       return "Less controversy"
        case .moreLocalChurches:     return "More local churches"
        case .exploreNewCreators:    return "Explore creators"
        case .morePrayerTestimonies: return "Prayer & testimonies"
        case .morePracticalFaith:    return "Practical faith"
        }
    }

    var icon: String {
        switch self {
        case .none:                  return "slider.horizontal.3"
        case .lighterTonight:        return "moon.stars"
        case .moreEncouragement:     return "heart.fill"
        case .moreBibleTeaching:     return "book.fill"
        case .lessControversy:       return "wind"
        case .moreLocalChurches:     return "mappin.circle.fill"
        case .exploreNewCreators:    return "sparkles"
        case .morePrayerTestimonies: return "hands.sparkles.fill"
        case .morePracticalFaith:    return "lightbulb.fill"
        }
    }

    var defaultDuration: HeyFeedDuration {
        switch self {
        case .none:                  return .session
        case .lighterTonight:        return .today
        case .moreEncouragement:     return .today
        case .moreBibleTeaching:     return .sevenDays
        case .lessControversy:       return .today
        case .moreLocalChurches:     return .sevenDays
        case .exploreNewCreators:    return .threeDays
        case .morePrayerTestimonies: return .threeDays
        case .morePracticalFaith:    return .sevenDays
        }
    }

    /// Ranking deltas to apply when this mode is active.
    var rankingAdjustments: [String: Double] {
        switch self {
        case .none: return [:]
        case .lighterTonight:
            return ["intense": -0.20, "heavy": -0.20, "controversial": -0.18, "debate": -0.25,
                    "calm": +0.15, "encouraging": +0.12]
        case .moreEncouragement:
            return ["encouragement": +0.25, "testimony": +0.20, "hope": +0.18]
        case .moreBibleTeaching:
            return ["bible_teaching": +0.28, "verse_reflection": +0.20, "practical_faith": +0.18]
        case .lessControversy:
            return ["controversial": -0.30, "debate": -0.28, "politics": -0.25,
                    "intense": -0.15, "confrontational": -0.20]
        case .moreLocalChurches:
            return ["local_churches": +0.30, "church_events": +0.22, "church_discovery": +0.20]
        case .exploreNewCreators:
            return ["discovery_boost": +0.25, "followed_penalty": -0.10]
        case .morePrayerTestimonies:
            return ["prayer_requests": +0.28, "testimonies": +0.25, "answered_prayers": +0.20]
        case .morePracticalFaith:
            return ["practical_faith": +0.28, "bible_teaching": +0.18, "inspirational": -0.10]
        }
    }
}

extension HeyFeedSessionMode: Identifiable {
    var id: String { rawValue }
}
