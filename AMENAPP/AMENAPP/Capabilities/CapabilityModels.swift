// CapabilityModels.swift
// AMEN Capabilities v1 — Frozen shared model types
//
// FROZEN after Wave 0 gate. Do not add, remove, rename, or retype anything here.
// File a CONTESTED blocker in Docs/Capabilities/BLOCKERS.md if a change is needed.
//
// Wire-format JSON keys are defined by CodingKeys where they differ from Swift names.
// See Docs/Capabilities/CONTRACTS.md §5 for the canonical type descriptions.

import Foundation

// MARK: - Surface & Source Enums

enum CapabilitySurface: String, Codable, CaseIterable, Equatable {
    case berean
    case messages
    case notes
}

enum ContextSource: String, Codable, CaseIterable, Equatable {
    case calendar
    case location
    case contacts
    case prayerHistory
    case readingHistory
    case notesContent
    case messagesMeta
    case churchProfile
}

enum ContextPolicy: String, Codable, CaseIterable, Equatable {
    case never
    case askEveryTime
    case whileUsing
    case always

    var displayName: String {
        switch self {
        case .never:        return "Never"
        case .askEveryTime: return "Ask Every Time"
        case .whileUsing:   return "While Using"
        case .always:       return "Always"
        }
    }
}

// MARK: - Context Grant

struct ContextGrant: Codable, Identifiable, Equatable {
    var id: String { source.rawValue }
    let source: ContextSource
    let policy: ContextPolicy
    let grantedAt: Date
    let updatedAt: Date
    let version: Int
}

// MARK: - Context Decision

struct ContextDecision: Codable, Equatable {
    let source: ContextSource
    let decision: ContextDecisionKind
    let reason: ContextDenialReason?
    let requestId: String
}

enum ContextDecisionKind: String, Codable, Equatable {
    case allowed
    case denied
    case promptRequired
}

enum ContextDenialReason: String, Codable, Equatable {
    case notGranted
    case backgroundDenied
    case notYetSupported
}

// MARK: - Capability

struct Capability: Codable, Identifiable, Equatable {
    let id: String
    let displayName: String
    let tagline: String
    let iconSymbol: String
    let surfaces: [CapabilitySurface]
    let requiredContext: [ContextSource]
    let optionalContext: [ContextSource]
    let entryFunction: String
    let minAppVersion: String
    let status: CapabilityStatus
    let tier: CapabilityTier
}

enum CapabilityStatus: String, Codable, Equatable {
    case active
    case disabled
}

enum CapabilityTier: String, Codable, Equatable {
    case free
    case plus
}

// MARK: - Prayer Card

struct PrayerCard: Codable, Identifiable, Equatable {
    let id: String
    let subject: PrayerSubject
    let category: PrayerCategory
    let detail: String
    let status: PrayerStatus
    let createdAt: Date
    let updatedAt: Date
    let reminders: [PrayerReminder]
    let followUps: [PrayerFollowUp]
}

struct PrayerSubject: Codable, Equatable {
    let type: PrayerSubjectType
    let displayName: String
    let linkedContactRef: String?

    enum CodingKeys: String, CodingKey {
        case type
        case displayName
        case linkedContactRef
    }
}

enum PrayerSubjectType: String, Codable, Equatable {
    case person
    case topic
}

enum PrayerCategory: String, Codable, CaseIterable, Equatable {
    case health
    case work
    case spiritual
    case family
    case other

    var displayName: String {
        switch self {
        case .health:    return "Health"
        case .work:      return "Work"
        case .spiritual: return "Spiritual"
        case .family:    return "Family"
        case .other:     return "Other"
        }
    }
}

enum PrayerStatus: String, Codable, Equatable {
    case active
    case answered
    case archived
}

struct PrayerReminder: Codable, Equatable {
    let rrule: String
    let nextFireAt: Date
}

struct PrayerFollowUp: Codable, Equatable {
    let dueAt: Date
    let status: PrayerFollowUpStatus
    let note: String?
}

enum PrayerFollowUpStatus: String, Codable, Equatable {
    case pending
    case done
    case dismissed
}

// MARK: - Scripture Reference

struct ScriptureRef: Codable, Identifiable, Equatable {
    var id: String { "\(blockId)-\(osisRef)" }
    let blockId: String
    let rangeStart: Int
    let rangeEnd: Int
    let osisRef: String
    let display: String

    enum CodingKeys: String, CodingKey {
        case blockId
        case rangeStart = "range_start"
        case rangeEnd   = "range_end"
        case osisRef
        case display
    }
}

// MARK: - Verse Card

struct VerseCard: Codable, Identifiable, Equatable {
    var id: String { "\(translation.rawValue)-\(osisRef)" }
    let osisRef: String
    let text: String
    let translation: BibleTranslation
    let display: String
}

enum BibleTranslation: String, Codable, CaseIterable, Equatable {
    case BSB
    case WEB
    case KJV

    var displayName: String {
        switch self {
        case .BSB: return "Berean Study Bible"
        case .WEB: return "World English Bible"
        case .KJV: return "King James Version"
        }
    }
}

// MARK: - Context Audit Entry

struct ContextAuditEntry: Codable, Identifiable, Equatable {
    var id: String { requestId }
    let source: ContextSource
    let capabilityId: String
    let decision: ContextDecisionKind
    let requestId: String
    let at: Date
}

// MARK: - Callable Response Wrappers

struct ContextGrantsResponse: Codable {
    let grants: [ContextGrant]
}

struct SetGrantResponse: Codable {
    let source: ContextSource
    let policy: ContextPolicy
    let version: Int
    let updatedAt: Date
}

struct CapabilityListResponse: Codable {
    let capabilities: [Capability]
}

struct PrayerCreateResponse: Codable {
    let cardId: String
    let dedupeWarning: PrayerDedupeWarning?
}

struct PrayerDedupeWarning: Codable, Equatable {
    let existingCardId: String
    let displayName: String
}

struct PrayerListResponse: Codable {
    let cards: [PrayerCard]
    let nextCursor: String?
}

struct ScriptureDetectResponse: Codable {
    let detections: [ScriptureRef]
}

struct ScriptureGetVersesResponse: Codable {
    let verses: [VerseCard]
}

struct ScriptureSearchResponse: Codable {
    let results: [ScriptureSearchResult]
}

struct ScriptureSearchResult: Codable, Identifiable, Equatable {
    var id: String { osisRef }
    let osisRef: String
    let display: String
    let snippet: String
}
