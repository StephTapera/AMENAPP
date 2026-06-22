// ChurchIntelligenceModels.swift
// Find a Church Intelligence — All models, enums, data types
// AMENAPP

import Foundation
import FirebaseFirestore

// MARK: - Typealiases

typealias ChurchArrivalConfidence = Double

// MARK: - ChurchVisitState

enum ChurchVisitState: String, Codable, CaseIterable {
    case none               = "none"
    case planning           = "planning"
    case arrived            = "arrived"
    case inService          = "inService"
    case postVisit          = "postVisit"
    case revisitSuggested   = "revisitSuggested"

    var displayName: String {
        switch self {
        case .none:             return "Not Visiting"
        case .planning:         return "Planning to Attend"
        case .arrived:          return "Arrived"
        case .inService:        return "In Service"
        case .postVisit:        return "Post-Visit"
        case .revisitSuggested: return "Return Suggested"
        }
    }
}

// MARK: - ChurchAssistPromptType

enum ChurchAssistPromptType: String, Codable {
    case planningToAttend       = "planningToAttend"
    case compareServices        = "compareServices"
    case firstVisitCompanion    = "firstVisitCompanion"
    case arrivedNeedsNotes      = "arrivedNeedsNotes"
    case arrivedChecklist       = "arrivedChecklist"
    case inServiceCaptureVerse  = "inServiceCaptureVerse"
    case inServicePrayerThought = "inServicePrayerThought"
    case postVisitReflection    = "postVisitReflection"
    case postVisitShare         = "postVisitShare"
    case revisitSuggestion      = "revisitSuggestion"

    /// True if this prompt type requires location access
    var requiresLocation: Bool {
        switch self {
        case .arrivedNeedsNotes, .arrivedChecklist,
             .inServiceCaptureVerse, .inServicePrayerThought,
             .firstVisitCompanion:
            return true
        default:
            return false
        }
    }

    /// True if this prompt is post-visit related
    var isPostVisit: Bool {
        switch self {
        case .postVisitReflection, .postVisitShare, .revisitSuggestion:
            return true
        default:
            return false
        }
    }

    /// True if this prompt is service-mode related
    var isServiceMode: Bool {
        switch self {
        case .inServiceCaptureVerse, .inServicePrayerThought:
            return true
        default:
            return false
        }
    }
}

// MARK: - ChurchLocationContext

struct ChurchLocationContext: Codable {
    var churchId: String
    var state: ChurchVisitState
    var enteredAt: Date?
    var exitedAt: Date?
    var dwellDurationSeconds: Int?
    var source: String
    var arrivalConfidence: Double

    init(
        churchId: String,
        state: ChurchVisitState = .none,
        enteredAt: Date? = nil,
        exitedAt: Date? = nil,
        dwellDurationSeconds: Int? = nil,
        source: String = "geofence",
        arrivalConfidence: Double = 0.0
    ) {
        self.churchId = churchId
        self.state = state
        self.enteredAt = enteredAt
        self.exitedAt = exitedAt
        self.dwellDurationSeconds = dwellDurationSeconds
        self.source = source
        self.arrivalConfidence = arrivalConfidence
    }
}

// MARK: - ChurchVisitSession

struct ChurchVisitSession: Codable, Identifiable {
    var id: String
    var churchId: String
    var userId: String
    var state: ChurchVisitState
    var plannedAt: Date?
    var arrivedAt: Date?
    var serviceStartedAt: Date?
    var exitedAt: Date?
    var dwellDurationSeconds: Int?
    var arrivalConfidence: Double
    var serviceConfidence: Double
    var exitConfidence: Double
    var noteIds: [String]
    var reflectionId: String?
    var prayerEntryId: String?
    var sharedPostId: String?
    var isPrivate: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        churchId: String,
        userId: String,
        state: ChurchVisitState = .none,
        plannedAt: Date? = nil,
        arrivedAt: Date? = nil,
        serviceStartedAt: Date? = nil,
        exitedAt: Date? = nil,
        dwellDurationSeconds: Int? = nil,
        arrivalConfidence: Double = 0.0,
        serviceConfidence: Double = 0.0,
        exitConfidence: Double = 0.0,
        noteIds: [String] = [],
        reflectionId: String? = nil,
        prayerEntryId: String? = nil,
        sharedPostId: String? = nil,
        isPrivate: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.churchId = churchId
        self.userId = userId
        self.state = state
        self.plannedAt = plannedAt
        self.arrivedAt = arrivedAt
        self.serviceStartedAt = serviceStartedAt
        self.exitedAt = exitedAt
        self.dwellDurationSeconds = dwellDurationSeconds
        self.arrivalConfidence = arrivalConfidence
        self.serviceConfidence = serviceConfidence
        self.exitConfidence = exitConfidence
        self.noteIds = noteIds
        self.reflectionId = reflectionId
        self.prayerEntryId = prayerEntryId
        self.sharedPostId = sharedPostId
        self.isPrivate = isPrivate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: CodingKeys for Firestore timestamp fields
    enum CodingKeys: String, CodingKey {
        case id
        case churchId
        case userId
        case state
        case plannedAt
        case arrivedAt
        case serviceStartedAt
        case exitedAt
        case dwellDurationSeconds
        case arrivalConfidence
        case serviceConfidence
        case exitConfidence
        case noteIds
        case reflectionId
        case prayerEntryId
        case sharedPostId
        case isPrivate
        case createdAt
        case updatedAt
    }
}

// MARK: - ChurchReflectionDraft

struct ChurchReflectionDraft: Codable, Identifiable {
    var id: String
    var userId: String
    var churchId: String
    var visitSessionId: String?
    var takeawayText: String
    var scriptureText: String?
    var prayerText: String?
    var shareTarget: String?
    var isPrivate: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        userId: String,
        churchId: String,
        visitSessionId: String? = nil,
        takeawayText: String = "",
        scriptureText: String? = nil,
        prayerText: String? = nil,
        shareTarget: String? = nil,
        isPrivate: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.churchId = churchId
        self.visitSessionId = visitSessionId
        self.takeawayText = takeawayText
        self.scriptureText = scriptureText
        self.prayerText = prayerText
        self.shareTarget = shareTarget
        self.isPrivate = isPrivate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - ChurchAssistState

struct ChurchAssistState: Codable {
    var enabled: Bool
    var allowLocationPrompts: Bool
    var allowVisitMemory: Bool
    var allowPostVisitPrompts: Bool
    var allowServiceMode: Bool
    var currentChurchId: String?
    var currentVisitSessionId: String?
    var currentVisitState: ChurchVisitState?
    var lastPromptType: ChurchAssistPromptType?
    var lastPromptAt: Date?
    var dismissedPromptTypes: [String]

    static var defaultState: ChurchAssistState {
        ChurchAssistState(
            enabled: true,
            allowLocationPrompts: false,
            allowVisitMemory: true,
            allowPostVisitPrompts: true,
            allowServiceMode: true,
            currentChurchId: nil,
            currentVisitSessionId: nil,
            currentVisitState: nil,
            lastPromptType: nil,
            lastPromptAt: nil,
            dismissedPromptTypes: []
        )
    }

    init(
        enabled: Bool = true,
        allowLocationPrompts: Bool = false,
        allowVisitMemory: Bool = true,
        allowPostVisitPrompts: Bool = true,
        allowServiceMode: Bool = true,
        currentChurchId: String? = nil,
        currentVisitSessionId: String? = nil,
        currentVisitState: ChurchVisitState? = nil,
        lastPromptType: ChurchAssistPromptType? = nil,
        lastPromptAt: Date? = nil,
        dismissedPromptTypes: [String] = []
    ) {
        self.enabled = enabled
        self.allowLocationPrompts = allowLocationPrompts
        self.allowVisitMemory = allowVisitMemory
        self.allowPostVisitPrompts = allowPostVisitPrompts
        self.allowServiceMode = allowServiceMode
        self.currentChurchId = currentChurchId
        self.currentVisitSessionId = currentVisitSessionId
        self.currentVisitState = currentVisitState
        self.lastPromptType = lastPromptType
        self.lastPromptAt = lastPromptAt
        self.dismissedPromptTypes = dismissedPromptTypes
    }
}

// MARK: - ChurchVisitInsights

struct ChurchVisitInsights: Codable {
    var totalVisits: Int
    var favoriteChurchIds: [String]
    var commonServiceTimes: [String]
    var lastVisitedChurchId: String?
    var lastVisitAt: Date?
    var topReflectionThemes: [String]

    init(
        totalVisits: Int = 0,
        favoriteChurchIds: [String] = [],
        commonServiceTimes: [String] = [],
        lastVisitedChurchId: String? = nil,
        lastVisitAt: Date? = nil,
        topReflectionThemes: [String] = []
    ) {
        self.totalVisits = totalVisits
        self.favoriteChurchIds = favoriteChurchIds
        self.commonServiceTimes = commonServiceTimes
        self.lastVisitedChurchId = lastVisitedChurchId
        self.lastVisitAt = lastVisitAt
        self.topReflectionThemes = topReflectionThemes
    }
}

// MARK: - ChurchPromptDecision

struct ChurchPromptDecision {
    var shouldShow: Bool
    var suppressReason: String?
    var prompt: ChurchAssistPromptType?

    static var suppress: ChurchPromptDecision {
        ChurchPromptDecision(shouldShow: false, suppressReason: "Default suppressed", prompt: nil)
    }
}
