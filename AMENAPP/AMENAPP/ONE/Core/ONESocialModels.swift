// ONESocialModels.swift
// ONE — Witness, Repair Flow, Vault, Legacy
// P0-F | FROZEN contracts. See CONTRACTS.md §9–13.

import Foundation

// MARK: - ONEWitness

struct ONEWitness: Codable, Identifiable, Sendable {
    let id: String
    let witnessUID: String              // the watcher
    let subjectUID: String              // the watched
    let season: ONEWitnessSeason
    var expiresAt: Date?               // nil = indefinite
    var mutualExposureLevel: ONEPrivacyMirrorLevel  // what subject sees back
    let createdAt: Date
    var renewedAt: Date?

    var isActive: Bool {
        guard let exp = expiresAt else { return true }
        return exp > Date()
    }
}

// MARK: - ONEWitnessSeason

struct ONEWitnessSeason: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case indefinite, liturgical, academic, event, custom
    }
    let kind: Kind
    var label: String?     // e.g. "Advent 2026", "Spring 2027", "Retreat 2026"
    var days: Int?         // for .custom

    static let indefinite = ONEWitnessSeason(kind: .indefinite)

    static func liturgical(_ l: String) -> ONEWitnessSeason { ONEWitnessSeason(kind: .liturgical, label: l) }
    static func academic(_ a: String) -> ONEWitnessSeason   { ONEWitnessSeason(kind: .academic, label: a) }
    static func event(_ e: String) -> ONEWitnessSeason      { ONEWitnessSeason(kind: .event, label: e) }
    static func custom(days d: Int) -> ONEWitnessSeason     { ONEWitnessSeason(kind: .custom, days: d) }

    var displayLabel: String {
        switch kind {
        case .indefinite: return "Ongoing"
        case .liturgical: return label ?? "Liturgical Season"
        case .academic:   return label ?? "Academic Term"
        case .event:      return label ?? "Event"
        case .custom:     return "\(days ?? 30) days"
        }
    }
}

// MARK: - ONERepairFlow

struct ONERepairFlow: Codable, Identifiable, Sendable {
    let id: String
    let initiatorUID: String
    let otherUID: String
    var phase: ONERepairPhase
    var initiatorAccepted: Bool
    var otherAccepted: Bool
    var toneChecks: [ONEToneCheck]
    var resolvedAt: Date?
    var exitedAt: Date?        // either party can exit instantly at any time
    let createdAt: Date

    var isBothAccepted: Bool { initiatorAccepted && otherAccepted }

    var isActive: Bool {
        phase == .active || phase == .toneCheck
    }
}

// MARK: - ONERepairPhase

enum ONERepairPhase: String, Codable, Sendable {
    case invited    // initiator sent; awaiting other's response
    case active     // both accepted
    case toneCheck  // AI tone preview shown before each message
    case resolved   // both marked resolved
    case exited     // one or both exited
}

// MARK: - ONEToneCheck

struct ONEToneCheck: Codable, Sendable {
    let messagePreview: String   // first 280 chars only
    let toneWarning: String?     // nil = tone OK; non-nil = caution shown
    let sentAt: Date?            // nil = not yet sent; user may still edit
}

// MARK: - ONEVaultItem

struct ONEVaultItem: Codable, Identifiable, Sendable {
    let id: String
    let ownerUID: String
    let encryptedPayload: Data   // AES-GCM; key in Secure Enclave; server cannot decrypt
    let iv: Data
    let contentType: ONEVaultContentType
    var timeReleaseAt: Date?
    var timeReleaseRecipientUIDs: [String]
    let accessRule: ONEVaultAccessRule
    let createdAt: Date
    var label: String            // encrypted client-side; local hint only

    var isAvailableNow: Bool {
        guard let release = timeReleaseAt else { return true }
        return release <= Date()
    }
}

// MARK: - ONEVaultContentType

enum ONEVaultContentType: String, Codable, Sendable {
    case reflection
    case media
    case document
    case moment
}

// MARK: - ONEVaultAccessRule

enum ONEVaultAccessRule: String, Codable, Sendable {
    case selfOnly
    case trustees   // see ONELegacyDirective
    case timeRelease
}

// MARK: - ONELegacyDirective

struct ONELegacyDirective: Codable, Identifiable, Sendable {
    let id: String
    let ownerUID: String
    var trustees: [ONETrustee]
    var bequests: [ONEMemoryBequest]
    var memorialization: ONEMemorialization
    var activatedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    var isActivated: Bool { activatedAt != nil }
}

// MARK: - ONETrustee

struct ONETrustee: Codable, Sendable {
    let uid: String
    let displayName: String
    var canActivate: Bool     // can trigger memorialization
    var canAccessVault: Bool
}

// MARK: - ONEMemoryBequest

struct ONEMemoryBequest: Codable, Identifiable, Sendable {
    let id: String
    let vaultItemID: String
    let recipientUID: String
    var deliverAt: Date       // "at activation" = activatedAt; or specific future date
    var message: String?
}

// MARK: - ONEMemorialization

enum ONEMemorialization: String, Codable, Sendable {
    case archiveProfile   // freeze; no new interactions
    case quietMemorial    // minimal presence; no engagement prompts
    case memorialPage     // explicit memorial with tribute space
    case deleteAll        // per user choice; trustees verify before execution
}
