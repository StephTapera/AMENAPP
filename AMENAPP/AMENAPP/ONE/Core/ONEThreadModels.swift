// ONEThreadModels.swift
// ONE — E2E Thread + Living Threads AI
// P0-F | FROZEN contracts. See CONTRACTS.md §4.
//
// E2E protocol: CryptoKit Double Ratchet (encryptionVersion "cr_1.0")
// Living Threads AI: on-device only; ONELivingThreadSummary is NEVER uploaded.

import Foundation

// MARK: - ONEThread

struct ONEThread: Codable, Identifiable, Sendable {
    let id: String
    let participantUIDs: [String]      // max 150 for groups
    let encryptionVersion: String      // "cr_1.0" (CryptoKit Double Ratchet)
    let isEphemeral: Bool
    var expiresAt: Date?
    // Living summary stored ONLY on device; field is transient — not serialized to Firestore
    var consentOverrides: [String: ONEMomentPermissions]   // per-participant permission overrides
    let createdAt: Date
    var lastActivityAt: Date
    var isArchived: Bool
}

// MARK: - ONEThreadMessage (Firestore: ciphertext only)

struct ONEThreadMessage: Codable, Identifiable, Sendable {
    let id: String
    let threadID: String
    let senderUID: String
    let ciphertext: Data          // AES-GCM ciphertext; server cannot decrypt
    let epoch: UInt64             // Double Ratchet epoch
    let senderDeviceID: String
    let sentAt: Date
    var expiresAt: Date?          // nil = no scheduled decay for this message
    var isReported: Bool          // true = evidence locked server-side
}

// MARK: - ONELivingThreadSummary (on-device only)

/// AI-distilled structured summary of a thread.
/// This type is NEVER serialized to Firestore or sent to any server.
/// The user must explicitly choose to share any part of it.
struct ONELivingThreadSummary: Sendable {
    var decisions: [String]
    var promises: [String]
    var importantDates: [ONELivingDate]
    var sharedLinks: [String]
    var tasks: [ONELivingTask]
    var prayerRequests: [String]
    var lastDistilledAt: Date
}

struct ONELivingDate: Sendable {
    let label: String
    let date: Date
}

struct ONELivingTask: Identifiable, Sendable {
    let id: String
    let description: String
    var assignedUID: String?
    var completedAt: Date?

    var isComplete: Bool { completedAt != nil }
}

// MARK: - ONEEphemeralGroupSettings

struct ONEEphemeralGroupSettings: Codable, Sendable {
    let groupID: String
    var expiresAt: Date
    var onExpiry: ONEGroupExpiryAction
}

enum ONEGroupExpiryAction: String, Codable, Sendable {
    case archive         // save as read-only archive
    case album           // convert to collaborative album
    case deleteAll       // delete everything; no recovery
    case highlightsOnly  // keep only "remembered" moments
}
