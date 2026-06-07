// SabbathModeModels.swift
// AMENAPP — SabbathMode
//
// Swift equivalents of the frozen TypeScript contracts in
// Prototypes/SabbathMode/contracts/. DO NOT add fields that are not in the
// contracts — do not invent Firestore paths. All paths are canonical per the
// contracts (users/{uid}/sabbath/config, users/{uid}/sabbathSessions/{date},
// users/{uid}/sabbathReflections/{id}).
//
// FROZEN — matches contract freeze date 2026-06-07.

import Foundation

// MARK: - Primitive enums (SabbathTypes.ts)

/// The day the user observes as their Sabbath.
enum SabbathDay: String, Codable, CaseIterable {
    case saturday
    case sunday
}

/// Lifecycle state of a Sabbath session.
/// - inactive:    Not in a Sabbath window; full app available.
/// - active:      Inside a Sabbath window; gate is enforced.
/// - steppedOut:  User deliberately exited for the day; banner persists.
enum SabbathState: String, Codable {
    case inactive
    case active
    case steppedOut
}

/// How the Sabbath window boundary is determined.
enum SabbathBoundary: String, Codable {
    case localMidnight
    case sundown
}

/// Surfaces accessible to the user during active Sabbath (SabbathTypes.ts).
/// Safety routes (emergency_support, trusted_circle, child_safety_report)
/// are NEVER listed here — they live in SABBATH_ALWAYS_ALLOWED.
enum SabbathSurface: String, Codable, CaseIterable {
    case scripture
    case prayer
    case bereanGuide
    case churchNotes
    case findChurch
    case spaces
    case familyQuestions
    case reflection
}

// MARK: - FROZEN Safety Allow-List (SabbathAllowList.ts)

/// FROZEN — matches SABBATH_ALWAYS_ALLOWED in contracts.
/// The gate MUST use this constant — never inline these strings.
/// Open items: "trusted_circle" and "child_safety_report" already exist
/// in AmenRoute and RestModeRoutes.allowed (RestModeGate.swift).
let SABBATH_ALWAYS_ALLOWED: [String] = [
    "emergency_support",    // → CrisisResourcesDetailView
    "trusted_circle",       // → TrustedCircleView (AmenRoute.trustedCircle)
    "child_safety_report",  // → ChildSafetyAgentStubView (AmenRoute.childSafetyReport)
]

// MARK: - Firestore-backed data models (SabbathModels.ts)

/// User's persisted Sabbath configuration.
/// Firestore path: users/{uid}/sabbath/config
struct SabbathConfig: Codable {
    /// The day the user observes as their Sabbath. Required; default: .sunday.
    var chosenDay: SabbathDay
    /// How the Sabbath window boundary is calculated. Default: .localMidnight.
    var boundary: SabbathBoundary
    /// IANA timezone string. iOS source of truth: TimeZone.current.identifier.
    var timezone: String
    /// Unix epoch milliseconds — set on initial document creation.
    var createdAt: Double
    /// Unix epoch milliseconds — updated on any field change.
    var updatedAt: Double
}

/// A single Sabbath observance session record.
/// Firestore path: users/{uid}/sabbathSessions/{yyyy-mm-dd}
struct SabbathSession: Codable {
    /// ISO date string matching the document ID (yyyy-mm-dd).
    var date: String
    /// Current lifecycle state of this session.
    var state: SabbathState
    /// Unix epoch milliseconds when the session was entered.
    var enteredAt: Double
    /// Unix epoch milliseconds when the user stepped out. Absent if not yet stepped out.
    var steppedOutAt: Double?
    /// Which allowed surfaces the user visited. NOT a score — digest only.
    var surfacesUsed: [SabbathSurface]
}

/// A private reflection written by the user.
/// Firestore path: users/{uid}/sabbathReflections/{id}
struct SabbathReflection: Codable {
    /// ISO date string of the Sabbath session this reflection belongs to.
    var sessionDate: String
    /// The prompt that was shown to the user.
    var prompt: String
    /// The user's private reflection body. Never surfaced to other users.
    var body: String
    /// Unix epoch milliseconds. Immutable.
    var createdAt: Double
}

/// Curated digest of what happened during the user's Sabbath.
/// Built server-side only — NEVER built client-side.
struct SabbathDigest: Codable {
    /// ISO date string of the session this digest summarises.
    var sessionDate: String
    /// One-line human-readable summary. Max 80 characters.
    var summaryLine: String
    /// Curated items — capped at 6 (server-enforced). Each item has a label
    /// and an amenapp:// deep link.
    var items: [SabbathDigestItem]
}

struct SabbathDigestItem: Codable {
    /// Short human-readable label for the item (max 40 chars).
    var label: String
    /// amenapp:// deep link.
    var deeplink: String
}

// MARK: - AI Task Registry (SabbathRouting.ts)

/// AI tasks available inside Sabbath Mode surfaces.
/// ALL tasks route through bereanChatProxy. Fail closed. Claude-only.
enum SabbathAITask: String, CaseIterable {
    case sabbathGuide      = "sabbath_guide"
    case familyQuestions   = "family_questions"
    case sermonPrep        = "sermon_prep"
    case devotional        = "devotional"
    case reflectionPrompt  = "reflection_prompt"
}

// MARK: - Runtime config defaults (SabbathConfig.ts)

/// Canonical runtime defaults for Sabbath Mode. Matches sabbathConfig in SabbathConfig.ts.
enum SabbathModeDefaults {
    static let defaultDay: SabbathDay = .sunday
    static let defaultBoundary: SabbathBoundary = .localMidnight

    enum StepOutPolicy {
        /// Maximum step-outs per Sabbath day. Enforced client + server.
        static let maxPerSabbath: Int = 1
        /// Confirmation sheet required before step-out.
        static let requiresConfirm: Bool = true
        /// Full access restored for the remainder of the local day.
        static let restoresFullDay: Bool = true
    }

    enum Digest {
        /// Max items in the night-of digest. Server enforces.
        static let maxItems: Int = 6
        /// Show digest exactly once per session.
        static let showOnce: Bool = true
    }

    enum Solidarity {
        static let enabled: Bool = true
        /// MUST remain false — never render a count.
        static let showCount: Bool = false
    }

    /// Allowed surfaces during active Sabbath. Matches sabbathConfig.allowedSurfaces.
    static let allowedSurfaces: [SabbathSurface] = SabbathSurface.allCases
}
