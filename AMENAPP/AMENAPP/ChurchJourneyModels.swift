// ChurchJourneyModels.swift
// AMENAPP
//
// Core data models for the Church Journey system:
//   Find Church → Plan Morning → Notes During Service → Reflect After
//
// These models mirror the Firestore schema defined in section 6 of the
// system spec and are the canonical Swift types used across all Journey views.

import Foundation
import FirebaseFirestore

// MARK: - Journey Status

enum ChurchJourneyStatus: String, Codable, CaseIterable, Equatable {
    case planned         = "planned"
    case prepActive      = "prep_active"
    case arrived         = "arrived"
    case notesActive     = "notes_active"
    case reflectionPending = "reflection_pending"
    case completed       = "completed"
    case cancelled       = "cancelled"

    var displayLabel: String {
        switch self {
        case .planned:            return "Planned"
        case .prepActive:         return "Prep Time"
        case .arrived:            return "Arrived"
        case .notesActive:        return "Taking Notes"
        case .reflectionPending:  return "Reflect"
        case .completed:          return "Completed"
        case .cancelled:          return "Cancelled"
        }
    }

    var isActive: Bool {
        switch self {
        case .planned, .prepActive, .arrived, .notesActive, .reflectionPending: return true
        case .completed, .cancelled: return false
        }
    }
}

// MARK: - Journey Options

struct ChurchJourneyOptions: Codable, Equatable {
    var coffeeEnabled: Bool
    var worshipPrepEnabled: Bool
    var scripturePrepEnabled: Bool
    var familyModeEnabled: Bool
    var noteModeEnabled: Bool
    var reflectionEnabled: Bool

    static let `default` = ChurchJourneyOptions(
        coffeeEnabled: false,
        worshipPrepEnabled: false,
        scripturePrepEnabled: true,
        familyModeEnabled: false,
        noteModeEnabled: true,
        reflectionEnabled: true
    )
}

// MARK: - Journey Timing

struct ChurchJourneyTiming: Codable, Equatable {
    var reminderAt: Date?
    var prepStartAt: Date?
    var departureAt: Date?
    var coffeeWindowStartAt: Date?
    var coffeeWindowEndAt: Date?
    var notesPromptAt: Date?
    var reflectionPromptAt: Date?

    /// Minutes until departure from now (nil if in the past or not set)
    var minutesUntilDeparture: Int? {
        guard let dep = departureAt else { return nil }
        let diff = dep.timeIntervalSinceNow / 60
        return diff > 0 ? Int(diff) : nil
    }
}

// MARK: - Journey Context Snapshot

struct ChurchJourneyContextSnapshot: Codable, Equatable {
    var expectedParkingComplexity: String?
    var weatherSummary: String?
    var routeEstimateMinutes: Int?
    var churchCafeAvailable: Bool
}

// MARK: - Journey Memory Inputs

struct ChurchJourneyMemoryInputs: Codable, Equatable {
    var usedRoutineId: String?
    var usedCoffeeTemplateId: String?
    var usedPreferenceProfileVersion: Int?
}

// MARK: - Journey Outputs

struct ChurchJourneyOutputs: Codable, Equatable {
    var suggestedPrepModules: [String]
    var suggestedScriptures: [String]
    var suggestedWorshipLinks: [WorkshopLink]
    var suggestedReminders: [String]

    struct WorkshopLink: Codable, Equatable, Identifiable {
        var id: String { title }
        let title: String
        let url: String
    }
}

// MARK: - Church Journey (top-level Firestore document)

struct ChurchJourney: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let churchId: String
    let churchNameSnapshot: String
    let serviceTimeId: String?
    let serviceLabelSnapshot: String?
    let serviceStartAt: Date
    let serviceEndAt: Date
    var status: ChurchJourneyStatus
    let planSource: String // "manual" | "routine" | "suggested"
    var timing: ChurchJourneyTiming
    var options: ChurchJourneyOptions
    let memoryInputs: ChurchJourneyMemoryInputs
    var contextSnapshot: ChurchJourneyContextSnapshot
    var outputs: ChurchJourneyOutputs
    var noteSessionId: String?
    var reflectionId: String?
    let createdAt: Date
    var updatedAt: Date

    var formattedServiceTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d • h:mm a"
        return formatter.string(from: serviceStartAt)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(serviceStartAt)
    }
}

// MARK: - Church Note Session

struct ChurchNoteSession: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let churchId: String
    let journeyId: String
    let serviceTimeId: String?
    var title: String
    let dateKey: String // "2026-04-20"
    var sermonTitle: String?
    var sermonSpeaker: String?
    var expectedScriptureRefs: [String]
    var attachedScriptureRefs: [String]
    var highlightsSummary: [NoteHighlight]
    var status: NoteSessionStatus
    var reflectionSeedGenerated: Bool
    let createdAt: Date
    var updatedAt: Date

    enum NoteSessionStatus: String, Codable {
        case active    = "active"
        case completed = "completed"
    }

    struct NoteHighlight: Codable, Equatable, Identifiable {
        var id: String { UUID().uuidString } // local only
        let type: ChurchNoteHighlightMeaning
        let text: String
    }
}

// MARK: - Note Highlight Meaning

enum ChurchNoteHighlightMeaning: String, Codable, CaseIterable, Equatable, Identifiable {
    case keyVerse    = "Key Verse"
    case conviction  = "Conviction"
    case prayer      = "Prayer"
    case action      = "Action"
    case encouragement = "Encouragement"

    var id: String { rawValue }

    var label: String { rawValue }

    var systemImage: String {
        switch self {
        case .keyVerse:      return "book.closed"
        case .conviction:    return "heart.circle"
        case .prayer:        return "hands.sparkles"
        case .action:        return "checkmark.circle"
        case .encouragement: return "sun.max"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .keyVerse:      return "Key verse highlight"
        case .conviction:    return "Conviction highlight"
        case .prayer:        return "Prayer point highlight"
        case .action:        return "Action step highlight"
        case .encouragement: return "Encouragement highlight"
        }
    }
}

// MARK: - Church Reflection

struct ChurchReflection: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let churchId: String
    let journeyId: String
    let noteSessionId: String?
    var primaryTakeaway: String?
    var applicationText: String?
    var prayerText: String?
    var verseToCarry: String?
    var actionItems: [ReflectionActionItem]
    var aiSummary: String?           // Server-written only
    var aiSuggestedPrayer: String?   // Server-written only
    var aiSuggestedActions: [ReflectionActionItem] // Server-written only
    var midweekReminderEnabled: Bool
    var midweekReminderAt: Date?     // Server-written only
    var status: ReflectionStatus
    let createdAt: Date
    var updatedAt: Date

    enum ReflectionStatus: String, Codable {
        case draft     = "draft"
        case completed = "completed"
    }

    var hasContent: Bool {
        [primaryTakeaway, applicationText, prayerText, verseToCarry]
            .compactMap { $0 }
            .contains(where: { !$0.isEmpty })
        || !actionItems.isEmpty
    }
}

struct ReflectionActionItem: Codable, Equatable, Identifiable {
    var id: String
    var text: String
    var completed: Bool

    init(id: String = UUID().uuidString, text: String, completed: Bool = false) {
        self.id = id
        self.text = text
        self.completed = completed
    }
}

// MARK: - Church Routine

struct ChurchRoutine: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let churchId: String
    let churchNameSnapshot: String
    var preferredServiceTimeId: String?
    var preferredServiceLabel: String?
    var daysOfWeek: [Int] // 1=Sun, 7=Sat
    var planningEnabled: Bool
    var coffeeEnabled: Bool
    var coffeeVendorType: String?
    var coffeeTemplateId: String?
    var worshipPrepEnabled: Bool
    var scripturePrepEnabled: Bool
    var familyModeEnabled: Bool
    var preferredArrivalBufferMinutes: Int
    var preferredPrepLeadMinutes: Int
    var preferredReminderLeadMinutes: Int
    var postServiceReflectionEnabled: Bool
    var midweekReminderEnabled: Bool
    var active: Bool
    let source: RoutineSource // "manual" | "suggested" | "learned"
    // confidenceScore is server-written only — not directly editable by client
    let createdAt: Date
    var updatedAt: Date

    enum RoutineSource: String, Codable {
        case manual    = "manual"
        case suggested = "suggested"
        case learned   = "learned"
    }

    var dayLabels: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return daysOfWeek.map { dayIndex in
            // dayIndex 1=Sun, 7=Sat; Calendar weekdaySymbols is 0=Sun
            let symbols = formatter.shortWeekdaySymbols ?? []
            let idx = max(0, (dayIndex - 1) % 7)
            return idx < symbols.count ? symbols[idx] : "\(dayIndex)"
        }
    }
}

// MARK: - Church Journey Plan (pre-save draft used in plan view)

/// Transient model used by the plan UI before the journey is saved.
/// Not persisted directly — converted to CreateJourneyRequest for the CF.
/// Uses the existing ChurchServiceTime struct (ChurchServiceTime.swift).
struct ChurchJourneyDraft {
    var church: ChurchEntity
    var selectedServiceTime: ChurchServiceTime?
    var options: ChurchJourneyOptions
    var routeEstimateMinutes: Int?
    var useRoutineId: String?
    var saveAsRoutine: Bool

    static func empty(for church: ChurchEntity) -> ChurchJourneyDraft {
        ChurchJourneyDraft(
            church: church,
            selectedServiceTime: nil,
            options: ChurchJourneyOptions.default,
            routeEstimateMinutes: nil,
            useRoutineId: nil,
            saveAsRoutine: false
        )
    }
}
