// BereanPrayerModels.swift
// AMENAPP — Berean Prayer Intelligence OS — Data models
//
// NOTE: BereanPrayerSensitivity is defined in BereanFormationModels.swift
// and is reused here. PrayerEntrySensitivity is a typealias used for clarity
// within this module.

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - Prayer Entry Status

enum BereanPrayerEntryStatus: String, Codable, CaseIterable {
    case active
    case answered
    case archived

    var displayName: String {
        switch self {
        case .active:   return "Active"
        case .answered: return "Answered"
        case .archived: return "Archived"
        }
    }
}

// MARK: - Prayer Category

enum BereanPrayerCategory: String, Codable, CaseIterable {
    case faith
    case healing
    case family
    case career
    case church
    case community
    case world
    case gratitude
    case other

    var displayName: String {
        switch self {
        case .faith:      return "Faith"
        case .healing:    return "Healing"
        case .family:     return "Family"
        case .career:     return "Career"
        case .church:     return "Church"
        case .community:  return "Community"
        case .world:      return "World"
        case .gratitude:  return "Gratitude"
        case .other:      return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .faith:      return "cross"
        case .healing:    return "heart.text.square"
        case .family:     return "figure.2.and.child.holdinghands"
        case .career:     return "briefcase"
        case .church:     return "building.columns"
        case .community:  return "person.3"
        case .world:      return "globe"
        case .gratitude:  return "hands.sparkles"
        case .other:      return "ellipsis.circle"
        }
    }
}

// MARK: - Prayer Entry Sensitivity
// Uses BereanPrayerSensitivity defined in BereanFormationModels.swift.
// Typealiased here for clarity within the Prayer module.

typealias PrayerEntrySensitivity = BereanPrayerSensitivity

// MARK: - Prayer Entry

struct BereanPrayerEntry: Identifiable, Codable {
    let id: String
    var subject: String
    var forWhom: String
    var body: String
    var status: BereanPrayerEntryStatus
    var category: BereanPrayerCategory
    var createdAt: Date
    var answeredAt: Date?
    var lastPrayedAt: Date?
    var isPrivate: Bool
    var sensitivity: PrayerEntrySensitivity

    // MARK: Firestore serialization

    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "id":          id,
            "subject":     subject,
            "forWhom":     forWhom,
            "body":        body,
            "status":      status.rawValue,
            "category":    category.rawValue,
            "createdAt":   Timestamp(date: createdAt),
            "isPrivate":   isPrivate,
            "sensitivity": sensitivity.rawValue
        ]
        if let answeredAt {
            data["answeredAt"] = Timestamp(date: answeredAt)
        }
        if let lastPrayedAt {
            data["lastPrayedAt"] = Timestamp(date: lastPrayedAt)
        }
        return data
    }

    init(
        id: String,
        subject: String,
        forWhom: String,
        body: String,
        status: BereanPrayerEntryStatus = .active,
        category: BereanPrayerCategory = .faith,
        createdAt: Date = Date(),
        answeredAt: Date? = nil,
        lastPrayedAt: Date? = nil,
        isPrivate: Bool = true,
        sensitivity: PrayerEntrySensitivity = .normal
    ) {
        self.id           = id
        self.subject      = subject
        self.forWhom      = forWhom
        self.body         = body
        self.status       = status
        self.category     = category
        self.createdAt    = createdAt
        self.answeredAt   = answeredAt
        self.lastPrayedAt = lastPrayedAt
        self.isPrivate    = isPrivate
        self.sensitivity  = sensitivity
    }

    init?(firestoreData data: [String: Any]) {
        guard
            let id        = data["id"] as? String,
            let subject   = data["subject"] as? String,
            let forWhom   = data["forWhom"] as? String,
            let statusRaw = data["status"] as? String,
            let status    = BereanPrayerEntryStatus(rawValue: statusRaw),
            let catRaw    = data["category"] as? String,
            let category  = BereanPrayerCategory(rawValue: catRaw),
            let createdTs = data["createdAt"] as? Timestamp,
            let isPrivate = data["isPrivate"] as? Bool
        else { return nil }

        self.id          = id
        self.subject     = subject
        self.forWhom     = forWhom
        self.body        = data["body"] as? String ?? ""
        self.status      = status
        self.category    = category
        self.createdAt   = createdTs.dateValue()
        self.isPrivate   = isPrivate

        if let sensRaw = data["sensitivity"] as? String {
            self.sensitivity = PrayerEntrySensitivity(rawValue: sensRaw) ?? .normal
        } else {
            self.sensitivity = .normal
        }

        if let ts = data["answeredAt"] as? Timestamp {
            self.answeredAt = ts.dateValue()
        }
        if let ts = data["lastPrayedAt"] as? Timestamp {
            self.lastPrayedAt = ts.dateValue()
        }
    }
}

// MARK: - Prayer Briefing

struct BereanPrayerBriefing: Identifiable {
    let id: String
    let date: Date
    var todaysFocus: [BereanPrayerEntry]       // max 5
    var suggestedScripture: String
    var answeredThisWeek: [BereanPrayerEntry]
    var peopleToIntercede: [String]            // display names only — privacy-safe
}

// MARK: - Prayer Session

struct BereanPrayerSession: Codable {
    let id: String
    let date: Date
    let durationSeconds: Int
    let entriesVisited: [String]               // entry IDs only

    var firestoreData: [String: Any] {
        [
            "id":              id,
            "date":            Timestamp(date: date),
            "durationSeconds": durationSeconds,
            "entriesVisited":  entriesVisited
        ]
    }
}

// MARK: - Prayer Streak
// isPrivate is always true — streak is NEVER shown publicly or compared to others.

struct BereanPrayerStreak: Codable {
    var currentStreak: Int
    var longestStreak: Int
    var lastPrayedDate: Date?
    let isPrivate: Bool           // always true — never expose publicly

    init(currentStreak: Int = 0, longestStreak: Int = 0, lastPrayedDate: Date? = nil) {
        self.currentStreak  = currentStreak
        self.longestStreak  = longestStreak
        self.lastPrayedDate = lastPrayedDate
        self.isPrivate      = true             // immutable — always private
    }

    init?(firestoreData data: [String: Any]) {
        self.currentStreak = data["currentStreak"] as? Int ?? 0
        self.longestStreak = data["longestStreak"] as? Int ?? 0
        self.isPrivate     = true

        if let ts = data["lastPrayedDate"] as? Timestamp {
            self.lastPrayedDate = ts.dateValue()
        } else {
            self.lastPrayedDate = nil
        }
    }
}
