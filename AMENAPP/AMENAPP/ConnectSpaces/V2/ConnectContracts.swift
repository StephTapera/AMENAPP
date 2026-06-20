//  ConnectContracts.swift
//  AMEN Connect V1 — Church Intelligence Layer · Swift mirror of contracts/connect.ts.
//  Wave 0 FROZEN: 2026-06-18. Source of truth is TypeScript; this mirrors it field-for-field.
//  Any change requires a contract-change note + re-freeze. Spec: AMEN_CONNECT_V1_SPEC.md.
//
//  NEW FILE — needs target membership added in Xcode (see CONNECT_WAVE0_AUDIT.md §6 / report).
//
//  SAFETY INVARIANTS (server-enforced; client re-asserts): a NextAction never carries another
//  member's data; a minor's PII is guardian-only; mediaRef is nil until MEDIA-GATE approves.

import Foundation

// MARK: - §3 assembleConnectHome

enum ConnectNextActionKind: String, Codable, Sendable {
    case attendService = "attend_service"
    case checkInKids = "check_in_kids"
    case joinGroup = "join_group"
    case rsvpEvent = "rsvp_event"
    case volunteer
    case watchSermon = "watch_sermon"
    case followUpPrayer = "follow_up_prayer"
    case readResource = "read_resource"
    case connectPerson = "connect_person"
    case completeProfile = "complete_profile"
    case planVisit = "plan_visit"
}

struct ConnectNextAction: Codable, Identifiable, Sendable {
    let id: String
    let kind: ConnectNextActionKind
    let title: String
    let subtitle: String?
    let whyShown: [String]            // transparent reasons, max 3
    let priority: Int
    let primaryActionLabel: String
    let deepLink: String
    let startsInMinutes: Int?
    let mediaRef: String?             // MEDIA-GATE; nil until approved
}

struct ConnectHomeRequest: Codable, Sendable {
    let churchId: String
    let nowIso: String
    let sessionId: String
}

struct ConnectPrayerUpdate: Codable, Identifiable, Sendable {
    var id: String { requestId }
    let requestId: String
    let title: String
    let status: String                // "active" | "answered"
    let followerCount: Int
    let authorIsMinor: Bool
    let answeredAt: String?
}

struct ConnectSermonRef: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let series: String?
    let lengthMinutes: Int?
    let topic: String?
    let mediaRef: String?
}

struct ConnectVolunteerNeed: Codable, Identifiable, Sendable {
    let id: String
    let ministryName: String
    let role: String
    let meets: String
}

struct ConnectResourceRef: Codable, Identifiable, Sendable {
    let id: String
    let kind: String                  // "sermon" | "course" | "devotional" | "pdf"
    let title: String
    let topic: String?
    let reason: String?
    let mediaRef: String?
}

/// Mirrors the TS discriminated union `ConnectSection`.
enum ConnectSection: Sendable {
    case prayerUpdates([ConnectPrayerUpdate])
    case newSermon([ConnectSermonRef])
    case volunteerNeeds([ConnectVolunteerNeed])
    case forYouResources([ConnectResourceRef])
}

struct ConnectCalmCap: Codable, Sendable {
    let maxActions: Int
    let infiniteScroll: Bool          // always false
    let guiltMechanics: Bool          // always false
}

struct ConnectHomeGreeting: Codable, Sendable {
    let name: String
    let dayLabel: String
}

struct ConnectHomeResponse: Sendable {
    let greeting: ConnectHomeGreeting
    let upNext: [ConnectNextAction]
    let sections: [ConnectSection]
    let calmCap: ConnectCalmCap
}

// MARK: - §4 askChurchConcierge

struct ConciergeRequest: Codable, Sendable {
    let churchId: String
    let query: String
    let childContextId: String?       // honored ONLY for a verified guardian of that child
}

struct ConciergeFact: Codable, Identifiable, Sendable {
    var id: String { label }
    let label: String
    let value: String
    let status: String?               // "ok" | "warn"
}

struct ConciergeAction: Codable, Identifiable, Sendable {
    var id: String { label }
    let label: String
    let deepLink: String
}

struct ConciergeCard: Codable, Sendable {
    let title: String
    let summary: String
    let facts: [ConciergeFact]
    let actions: [ConciergeAction]?
    let sources: [String]             // REQUIRED — no hallucinated facts
}

// MARK: - §7 other V1 callables

struct ConnectMinistryRec: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let meets: String
    let openSpots: Int?
    let lifeStage: String?
    let leaderAvatarRef: String?      // MEDIA-GATE; nil until approved
    let whyShown: [String]
}

enum ConnectVisitPhase: String, Codable, Sendable {
    case before, dayOf = "day_of", after
}

struct ConnectVisitStep: Codable, Identifiable, Sendable {
    let id: String
    let label: String
    let detail: String?
    let deepLink: String?
    let guardianGated: Bool           // child steps render only to a verified guardian
}

struct VisitAssistantCard: Codable, Sendable {
    let phase: ConnectVisitPhase
    let title: String
    let steps: [ConnectVisitStep]
}

// MARK: - §5.1 verified guardian link primitive

enum GuardianLinkStatus: String, Codable, Sendable {
    case pending, verified, revoked
}

struct GuardianEvidence: Codable, Sendable {
    let kind: String                  // "staff_attested" | "pickup_code" | "invite_acceptance"
    let reference: String?
}

struct GuardianLink: Codable, Identifiable, Sendable {
    let id: String
    let churchId: String
    let guardianUid: String
    let childId: String
    let status: GuardianLinkStatus    // server-only
    let verifiedAt: String?           // server-only
    let createdAt: String
}

struct RequestGuardianLinkRequest: Codable, Sendable {
    let churchId: String
    let childId: String
    let evidence: GuardianEvidence
}

/// Child status — returned ONLY to a verified guardian (function returns 403 otherwise).
struct ChildStatus: Codable, Sendable {
    let childId: String
    let checkedIn: Bool
    let ageGroup: String?
    let building: String?
    let pickupCode: String?
    let allergies: [String]?          // SENSITIVE — guardian-only, never logged
}
