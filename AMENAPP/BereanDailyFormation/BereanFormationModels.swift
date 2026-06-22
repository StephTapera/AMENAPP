// BereanFormationModels.swift
// AMENAPP — Berean Daily Formation Companion — Data models

import SwiftUI

// MARK: - Card types

enum BereanFormationCardType: String {
    case verse, plan, prayer, sanctuary, study, memory, seasonal
}

// MARK: - Sensitivity

enum BereanPrayerSensitivity: String, Codable, CaseIterable {
    case normal, tender, crisis
}

// MARK: - Prayer item

struct BereanPrayerItem: Identifiable {
    let id: String
    let subject: String
    let forWhom: String
    let prayedOn: String    // ISO date string "YYYY-MM-DD"
    let status: String      // "active" | "answered"
    let sensitivity: BereanPrayerSensitivity
}

// MARK: - Reading plan

struct BereanReadingPlan {
    let name: String
    let currentDay: Int
    let totalDays: Int
    let todayPassageRef: String     // e.g. "Matthew 6:33"
    let todayPassageRange: String   // e.g. "Matthew 6:25–34"
    var progress: Double { Double(currentDay) / Double(totalDays) }
}

// MARK: - Sanctuary

struct BereanSanctuary: Identifiable {
    let id: String
    let name: String
    let openPrayerRequests: Int
    let activeThreads: Int
    let recentActivity: String
}

// MARK: - Highlight

struct BereanHighlight: Identifiable {
    let id: String
    let verseRef: String
    let note: String
    let savedOn: String  // ISO date string
}

// MARK: - Memory verse

struct BereanMemoryVerse: Identifiable {
    let id: String
    let verseRef: String
    let srsDueDate: String   // ISO date string
    let strength: Double     // 0.0 – 1.0
    let streak: Int
}

// MARK: - Seasonal

struct BereanSeasonalRhythm {
    let liturgicalSeason: String
    let prompt: String
}

// MARK: - Verse (mock-gated)

struct BereanVerse {
    let text: String      // always prefixed with "[MOCK — ESV]" etc.
    let citation: String
    let isMock: Bool
}

// MARK: - Card payload (type-erased per card type)

enum BereanFormationCardData {
    case verse(BereanVerse, passageRange: String)
    case plan(BereanReadingPlan)
    case prayer(BereanPrayerItem)
    case sanctuary(BereanSanctuary)
    case study(BereanHighlight, verse: BereanVerse)
    case memory(BereanMemoryVerse, verse: BereanVerse)
    case seasonal(BereanSeasonalRhythm)
}

// MARK: - Formation card (arc item + feed item)

struct BereanFormationCard: Identifiable {
    let id: String
    let cardType: BereanFormationCardType
    let typeLabel: String        // "Daily Verse", "Reading Plan", etc.
    let icon: String             // SF symbol name OR emoji fallback
    let source: String           // "readingPlan" | "prayerList" | etc.
    let sourceDetail: String
    let previewText: String
    let verseChipRef: String?    // verse reference shown as chip, if any
    let data: BereanFormationCardData
}

// MARK: - Onboarding result

struct BereanFormationPrefs {
    let selectedTopics: Set<String>
    let consents: [String: Bool]
}

// MARK: - Mock user

struct BereanMockUser {
    static let id               = "user_001"
    static let name             = "Jordan"
    static let tradition        = "non-denominational"
    // TODO(legal): was ESV (Crossway, copyrighted) — changed to KJV per AMEN-CONTENT-001
    static let translationPref  = "KJV"
}

// MARK: - Seasonal rhythm (liturgical calendar)

extension BereanSeasonalRhythm {
    static func current() -> BereanSeasonalRhythm {
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 12, 1:
            return BereanSeasonalRhythm(
                liturgicalSeason: "Advent / Christmas",
                prompt: "Advent is a season of waiting and longing. Where is God asking you to be patient today?"
            )
        case 2, 3:
            return BereanSeasonalRhythm(
                liturgicalSeason: "Epiphany / Lent",
                prompt: "Lent invites honest self-examination. What is God revealing to you about yourself?"
            )
        case 4, 5:
            return BereanSeasonalRhythm(
                liturgicalSeason: "Easter / Eastertide",
                prompt: "Resurrection changes everything. Where do you need to live out of the hope of Easter today?"
            )
        default:
            return BereanSeasonalRhythm(
                liturgicalSeason: "Ordinary Time",
                prompt: "Ordinary Time invites faithful attention to the everyday. Where is the sacred hiding in your routine today?"
            )
        }
    }
}
