// CommsContracts.swift
// AMEN Comms OS — Shared Contracts (Phase 0 Foundation)
//
// Frozen interfaces for the Comms OS build. No agent may invent alternate versions.
// All features are off by default and gated by AMENFeatureFlags.

import Foundation

// MARK: - Source Citation Envelope
// Every AI-extracted item carries this envelope.
// Nothing is confirmed without explicit human action with the correct permission.

struct CommsSourceCitation: Codable {
    let items: [CommsCitedItem]
}

struct CommsCitedItem: Codable {
    let value: String
    let confidence: Double
    let status: CommsCitationStatus
    let sourceMessageIds: [String]
}

enum CommsCitationStatus: String, Codable {
    case possible
    case proposed
    case confirmed
    case stale
    case outdated
}

// MARK: - Relevance Score + Intent Envelope
// Used by ranking (inbox ordering) and intent routing (command palette).
// Server-side only; the client is a read-only consumer.

struct CommsRelevanceScore: Codable {
    let score: Double        // 0.0 – 1.0
    let reasons: [String]    // e.g. ["unanswered mention", "open decision"]
    let intent: String?      // nil when not an intent-routing context
    let confidence: Double   // 0.0 – 1.0
}

// MARK: - Correction Feedback
// Captured when a user accepts, dismisses, or corrects a smart output.
// Stored per-user at users/{uid}/commsFeedback/{id}.

struct CommsFeedbackRecord: Codable {
    let id: String
    let userId: String
    let threadId: String
    let itemType: CommsItemType
    let itemId: String
    let action: CommsFeedbackAction
    let correctedValue: String?
    let createdAt: Date
}

enum CommsFeedbackAction: String, Codable {
    case accepted
    case dismissed
    case corrected
}

enum CommsItemType: String, Codable {
    case decision
    case followUp
    case summary
    case rankScore
    case mediaJob
}

// MARK: - Callable Function Names (frozen)
// All Comms OS AI is server-side only. These are the only callable names
// the client may invoke for Comms OS features.

enum CommsFunctionName {
    static let rankRelevance        = "comms_rankRelevance"
    static let routeIntent          = "comms_routeIntent"
    static let generateSmartContext = "comms_generateSmartContext"
    static let generateCatchUp      = "comms_generateCatchUp"
    static let submitFeedback       = "comms_submitFeedback"
    static let processMediaJob      = "comms_processMediaJob"
    static let getMediaJobStatus    = "comms_getMediaJobStatus"
    static let suggestAsyncReply    = "comms_suggestAsyncReply"
}

// MARK: - Firestore Path Constants (frozen)
// All Comms OS data lives under the comms/ namespace.

enum CommsFirestorePath {
    static func threadSummaries(threadId: String) -> String  { "comms/threads/\(threadId)/summaries" }
    static func threadDecisions(threadId: String) -> String  { "comms/threads/\(threadId)/decisions" }
    static func threadFollowUps(threadId: String) -> String  { "comms/threads/\(threadId)/followUps" }
    static let mediaJobs = "comms/mediaJobs"

    static func userDigests(uid: String) -> String           { "users/\(uid)/commsDigests" }
    static func userScores(uid: String) -> String            { "users/\(uid)/commsScores" }
    static func userFeedback(uid: String) -> String          { "users/\(uid)/commsFeedback" }
    static func userPresence(uid: String) -> String          { "users/\(uid)/presence" }
}

// MARK: - Media Job
// Async media intelligence job record stored at comms/mediaJobs/{jobId}.
// Media URL is passed in the request only — never stored in the job record
// returned to the client to prevent leaking signed URLs.

enum CommsMediaJobStatus: String, Codable {
    case queued
    case processing
    case completed
    case failed
    case accessDenied
}

struct CommsMediaJobRecord: Codable {
    let id: String
    let threadId: String
    let requestedByUserId: String
    var status: CommsMediaJobStatus
    let requestedAt: Date
    var completedAt: Date?
    var errorMessage: String?
    // Results live in a subcollection to prevent partial-data exposure on failure.
    var resultAvailable: Bool
}

// MARK: - Presence
// Approximate, opt-in, self-only. Expires via TTL in Firestore.

struct CommsPresenceRecord: Codable {
    let uid: String
    let status: SmartPresenceStatus
    let updatedAt: Date
    let expiresAt: Date
    let isOptedIn: Bool
}
