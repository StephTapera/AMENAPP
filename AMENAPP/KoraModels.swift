// KoraModels.swift
// AMENAPP
//
// Codable Firestore models for the Kora feature (spiritual accountability circles).

import SwiftUI
import FirebaseFirestore

// MARK: - Enums

enum KoraPurpose: String, Codable, CaseIterable {
    case spiritualHealth
    case marriage
    case grief
    case team
    case accountability
    case custom

    var label: String {
        switch self {
        case .spiritualHealth: return "Spiritual Health"
        case .marriage:        return "Marriage"
        case .grief:           return "Grief"
        case .team:            return "Team"
        case .accountability:  return "Accountability"
        case .custom:          return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .spiritualHealth: return "heart.fill"
        case .marriage:        return "person.2.fill"
        case .grief:           return "cloud.rain.fill"
        case .team:            return "person.3.fill"
        case .accountability:  return "checkmark.seal.fill"
        case .custom:          return "star.fill"
        }
    }
}

enum KoraRhythm: String, Codable, CaseIterable {
    case weekly
    case biweekly
    case monthly

    var label: String {
        switch self {
        case .weekly:    return "Weekly"
        case .biweekly:  return "Biweekly"
        case .monthly:   return "Monthly"
        }
    }

    var days: Int {
        switch self {
        case .weekly:    return 7
        case .biweekly:  return 14
        case .monthly:   return 30
        }
    }
}

enum KoraCheckInStatus: String, Codable {
    case open
    case closed
    case summarized
}

enum KoraMood: String, Codable, CaseIterable {
    case thriving
    case growing
    case struggling
    case needsSupport

    var label: String {
        switch self {
        case .thriving:     return "Thriving"
        case .growing:      return "Growing"
        case .struggling:   return "Struggling"
        case .needsSupport: return "Needs Support"
        }
    }

    var colorHex: String {
        switch self {
        case .thriving:     return "22C55E"
        case .growing:      return "EAB308"
        case .struggling:   return "F97316"
        case .needsSupport: return "EF4444"
        }
    }

    var icon: String {
        switch self {
        case .thriving:     return "sun.max.fill"
        case .growing:      return "leaf.fill"
        case .struggling:   return "cloud.fill"
        case .needsSupport: return "sos.circle.fill"
        }
    }
}

enum KoraShareScope: String, Codable {
    case `private`
    case circle
    case workspace
}

// MARK: - Models

struct KoraCircle: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var workspaceId: String
    var name: String
    var purpose: KoraPurpose
    var memberIds: [String]
    var memberCount: Int
    var rhythmType: KoraRhythm
    var rhythmDayOfWeek: Int?
    var rhythmHour: Int?
    var aiCheckInEnabled: Bool
    var lastCheckInAt: Date?
    var nextCheckInAt: Date
    var coverColorHex: String
    var isPrivate: Bool
    var createdAt: Date?
}

struct KoraCheckIn: Identifiable, Codable {
    @DocumentID var id: String?
    var circleId: String
    var workspaceId: String
    var triggeredBy: String
    var question: String
    var aiSummary: String?
    var aiInsights: [String]
    var status: KoraCheckInStatus
    var openedAt: Date?
    var closedAt: Date?
}

struct KoraCheckInResponse: Identifiable, Codable {
    @DocumentID var id: String?
    var checkInId: String
    var circleId: String
    var authorId: String
    var responseText: String
    var mood: KoraMood
    var isPrivate: Bool
    var createdAt: Date?
}

struct KoraJournalEntry: Identifiable, Codable {
    @DocumentID var id: String?
    var circleId: String
    var authorId: String
    var content: String
    var sharedWith: KoraShareScope
    var aiReflection: String?
    var createdAt: Date?
}
