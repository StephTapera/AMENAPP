// ThresholdContracts.swift
// AMEN — THRESHOLD Smart Profile / Identity Switcher
//
// W0 FROZEN CONTRACTS — 2026-06-16
// D1 CONFIRMED: Contexts under one verified identity (personal/ministry/creator/org).
// Linked-separate-accounts deferred to v2.
//
// MUTATION POLICY: Nothing in this file changes after W0 freeze without a logged,
// human-approved change record. Add a CHANGE: comment with date + reason if editing.
//
// Anti-engagement contract: see ThresholdAntiEngagementNote.swift.

import Foundation

// MARK: - Type Aliases (stable identifiers)

/// Opaque identifier for a profile context (one identity may hold multiple).
typealias ProfileID = String

/// Opaque identifier for the single verified human behind all contexts (D1).
typealias VerifiedIdentityID = String

/// Reference token to a stored asset (avatar, media, etc.). Resolver is caller's concern.
typealias AssetRef = String

/// Reference token to a per-profile E2EE key context. Loaded only after step-up auth (D4).
typealias KeyRef = String

/// Identifies a surface within the app where state can be remembered (e.g. "feed", "inbox").
typealias SurfaceID = String

/// Identifies a Berean conversation thread for draft persistence.
typealias ThreadID = String

// MARK: - Identity & Profiles

enum ProfileType: String, Codable, Sendable, CaseIterable {
    case personal
    case ministry
    case creator
    case org
}

/// Elevated capabilities that require step-up authentication (L3 / ReauthGate).
enum ProfileCapability: String, Codable, Sendable, CaseIterable {
    case post
    case dm
    case moderate           // elevated — content moderation surface
    case guardianTools      // elevated — child-safety surface (maxAge: 300s)
    case orgAdmin           // elevated — org management
    case keyManagement      // elevated — account/key recovery (maxAge: 120s)

    var requiresStepUp: Bool {
        switch self {
        case .post, .dm:                      return false
        case .moderate, .guardianTools,
             .orgAdmin, .keyManagement:       return true
        }
    }
}

/// A single profile context for one verified human. (D1: one identity, multiple contexts.)
struct ProfileDescriptor: Codable, Identifiable, Sendable {
    let id: ProfileID
    let identityId: VerifiedIdentityID      // the one human behind all contexts (D1)
    let type: ProfileType
    let handle: String
    let displayName: String
    let avatarRef: AssetRef?
    let trustTier: TrustTier                // reuses existing top-level TrustTier (StudioModels)
    let capabilities: Set<ProfileCapability>
    let e2eeKeyRef: KeyRef?                 // loaded post-step-up only (D4)
}

// MARK: - Remembered State (L1 — ProfileSessionStore)

/// Snapshot of the composer state for a given surface. Content is opaque to Threshold.
struct DraftSnapshot: Codable, Sendable {
    let surfaceId: SurfaceID
    let textContent: String
    let attachmentRefs: [AssetRef]
    let savedAt: Date
}

/// Scroll position anchor for a surface. Opaque reference, resolved by the surface.
struct ScrollAnchor: Codable, Sendable {
    let surfaceId: SurfaceID
    let anchorId: String            // post id, message id, or similar
    let offsetPoints: Double        // points from top of anchor item
}

/// Read position within a feed or thread.
struct ReadCursor: Codable, Sendable {
    let surfaceId: SurfaceID
    let lastSeenId: String
    let seenAt: Date
}

/// Unread/badge counts snapshot per profile. Captured on switch-away; restored on switch-in.
struct BadgeCounts: Codable, Sendable {
    var dmUnread: Int
    var notificationUnread: Int
    var prayerUnread: Int

    static let zero = BadgeCounts(dmUnread: 0, notificationUnread: 0, prayerUnread: 0)
}

/// Full remembered state for one profile context. Encrypted at rest; never mirrored to server (D5).
struct ProfileSessionState: Codable, Sendable {
    var composerDrafts: [SurfaceID: DraftSnapshot]
    var bereanThreadDrafts: [ThreadID: String]
    var readCursors: [SurfaceID: ReadCursor]
    var scrollPositions: [SurfaceID: ScrollAnchor]
    var lastActiveSurface: SurfaceID?
    var badgeSnapshot: BadgeCounts
    var updatedAt: Date

    static let empty = ProfileSessionState(
        composerDrafts: [:],
        bereanThreadDrafts: [:],
        readCursors: [:],
        scrollPositions: [:],
        lastActiveSurface: nil,
        badgeSnapshot: .zero,
        updatedAt: .distantPast
    )
}

// MARK: - Prediction Signals (L2 — ThresholdRanker)
// All built on-device. None of these types are serialized to any server. (D2)

enum TimeBucket: String, Codable, Sendable, CaseIterable {
    case earlyMorning   // 04:00–06:59
    case morning        // 07:00–11:59
    case midday         // 12:00–14:59
    case afternoon      // 15:00–17:59
    case evening        // 18:00–20:59
    case night          // 21:00–03:59
}

enum Weekday: Int, Codable, Sendable, CaseIterable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
}

/// How the user arrived at Threshold (cold launch, deep link, share sheet, etc.).
enum EntryContext: String, Codable, Sendable {
    case coldLaunch
    case deepLink
    case shareSheet
    case notificationTap
    case inAppSwitch        // user tapped the avatar/switcher from within the app
}

/// Exponentially-decayed usage weight for a profile. Half-life ~7 days.
/// Built from local analytics only; never sent to server. (D2)
struct DecayedUsage: Codable, Sendable {
    let profileId: ProfileID
    let weight: Double      // 0…1, higher = more recent/frequent use
    let lastActiveAt: Date
}

/// The full on-device signal built when the user opens Threshold. (D2)
struct SwitchSignal: Sendable {
    let now: Date
    let timeBucket: TimeBucket
    let dayOfWeek: Weekday
    let isLikelyServiceWindow: Bool         // e.g. Sun 08:00–12:00, configurable
    let liturgicalSeason: LiturgicalSeasonType   // reuses existing LiturgicalSeasonType enum
    let entrySurface: EntryContext
    let deepLinkProfileHint: ProfileID?     // e.g. opened a Space this profile owns
    let networkClass: NetworkClass          // reuses existing NetworkClass (GlobalResilienceContracts)
    let recentUsage: [ProfileID: DecayedUsage]
}

/// The pre-staged action Threshold thinks the user came to perform.
/// Optional; shown only when confidence is high. (D3)
enum PredictedIntent: String, Sendable {
    case post
    case viewFeed
    case openDMs
    case joinPrayer
    case openBerean
    case scheduler
}

/// One ranked candidate returned by ThresholdRanker.
struct RankedProfile: Sendable {
    let profileId: ProfileID
    let score: Double           // 0…1
    /// Human-readable explanation of the top-contributing feature. (D3)
    /// Shown as a chip ("Usually here Sunday mornings"). One sentence, ≤ 60 chars.
    let reason: String
}

/// Full prediction output. Ranked highest-first. (D2, D3)
struct SwitchPrediction: Sendable {
    let ranked: [RankedProfile]
    let predictedIntent: PredictedIntent?   // optional pre-stage suggestion
    let confidence: Double                  // 0…1; used to decide whether to show intent chip
}

/// Contract for the on-device weighted scorer. Implementations must not make network calls. (D2)
protocol ThresholdRanking: Sendable {
    /// Rank profiles using on-device signals only. Must be pure and deterministic for the same input.
    func rank(_ profiles: [ProfileDescriptor], _ signal: SwitchSignal) -> SwitchPrediction
}

// MARK: - Security / Re-auth (L3 — ReauthGate)

enum ReauthRequirement: Sendable, Equatable {
    case none
    case biometricOrPasscode
    /// User must have authenticated within `maxAge` seconds, otherwise re-prompt.
    case biometricOrPasscodeAndRecentAuth(maxAge: TimeInterval)
}

/// Contract for the step-up auth policy. Implementations must fail-closed (deny on error). (D4)
protocol ReauthPolicy: Sendable {
    /// Returns the authentication requirement before switching into `profile`.
    /// A failed or cancelled step-up must leave the active profile unchanged.
    func requirement(switchingTo profile: ProfileDescriptor) -> ReauthRequirement
}

// MARK: - Feature Flags (default OFF — D6)
// Canonical names used by Remote Config. All default to false in main.

enum ThresholdFlag {
    /// Master gate — no Threshold UI surfaces if false.
    static let enabled          = "threshold.enabled"
    /// L2 prediction (off → alphabetical / recency fallback).
    static let prediction       = "threshold.prediction"
    /// L1 remembered-state restore.
    static let rememberedState  = "threshold.rememberedState"
    /// Auto-switch to top prediction (opt-in; off by default per D6).
    static let autoSelect       = "threshold.autoSelect"
}
