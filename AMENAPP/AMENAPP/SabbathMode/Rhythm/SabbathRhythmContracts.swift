// SabbathRhythmContracts.swift
// AMENAPP — SabbathMode / Rhythm (Sabbath Mode v2, Wave 0)
//
// FROZEN CONTRACTS — Sabbath Mode v2 "subtraction" architecture.
// The design law: "Selah becomes smaller when it's succeeding." In Sabbath the
// UI's job is REMOVAL, not addition.
//
// NAMING NOTE: the v2 spec names these types `SabbathState`, `SubtractionPolicy`,
// `TriggerSource`, `RestSignal`, `SafetyInvariant`. The existing v1 module already
// defines `SabbathState` (SabbathModeModels.swift) with different semantics, so to
// stay non-destructive every v2 contract is prefixed `Sabbath…` (matching the
// existing module convention: SabbathConfig, SabbathSession). Spec→code mapping:
//   SabbathState      → SabbathRhythmState
//   SubtractionPolicy → SabbathSubtractionPolicy
//   TriggerSource     → SabbathTriggerSource
//   RestSignal        → SabbathRestSignal
//   SafetyInvariant   → SabbathSafetyInvariant
//
// All v2 behaviour is gated behind `sabbath_mode_enabled` (default OFF). When the
// flag is off or the state is `.normal`, nothing here changes app behaviour.

import Foundation

// MARK: - Contract 1: SabbathRhythmState (spec: SabbathState)

/// The Sabbath rhythm state machine.
/// `Normal → Rest → Presence → HolyGround`, deepening toward silence.
/// Wave 0 ships `.normal` and `.rest`; `.presence` and `.holyGround` are
/// defined-but-unused, reserved for Wave 1.
enum SabbathRhythmState: String, Codable, CaseIterable {
    /// Full app available. No subtraction.
    case normal
    /// Feeds, metrics, badges and streaks are removed; the screen quiets.
    case rest
    /// Wave 1 — sermon / worship. Defined, not yet driven.
    case presence
    /// Wave 1 — prayer / silence; single-surface guarantee. Defined, not yet driven.
    case holyGround
}

// MARK: - Contract 2: SabbathSubtractionPolicy (spec: SubtractionPolicy)

/// Declarative, per-state description of what is *removed* from the UI.
/// This is the SINGLE SOURCE OF TRUTH for hiding (Invariant I3): no surface may
/// hide content ad hoc — it must read a field on the policy for the active state.
struct SabbathSubtractionPolicy: Equatable {
    var hideFeeds: Bool
    var hideMetrics: Bool
    var hideBadges: Bool
    var hideStreaks: Bool
    var suppressInAppNotifications: Bool
    var reduceMotion: Bool
    var calmPalette: Bool
    var hideNavigation: Bool

    /// Nothing removed — the `.normal` baseline.
    static let none = SabbathSubtractionPolicy(
        hideFeeds: false,
        hideMetrics: false,
        hideBadges: false,
        hideStreaks: false,
        suppressInAppNotifications: false,
        reduceMotion: false,
        calmPalette: false,
        hideNavigation: false
    )

    /// `.rest` — quiet Selah's feeds, metrics, badges, streaks and notifications;
    /// soften motion; calm the palette; minimise primary navigation.
    static let rest = SabbathSubtractionPolicy(
        hideFeeds: true,
        hideMetrics: true,
        hideBadges: true,
        hideStreaks: true,
        suppressInAppNotifications: true,
        reduceMotion: true,
        calmPalette: true,
        hideNavigation: true
    )

    /// `.presence` — you are *present* in a gathering (sermon / worship). The noisy
    /// social layer is subtracted and the palette calms, but primary navigation stays
    /// available so you can still open the Bible or Church Notes during the service.
    /// The single difference from `.rest`: navigation is kept (`hideNavigation: false`).
    static let presence = SabbathSubtractionPolicy(
        hideFeeds: true,
        hideMetrics: true,
        hideBadges: true,
        hideStreaks: true,
        suppressInAppNotifications: true,
        reduceMotion: true,
        calmPalette: true,
        hideNavigation: false
    )

    /// `.holyGround` — prayer / silence. The deepest state: everything is removed and a
    /// single calm surface is guaranteed. Booleans match `.rest` (total quiet); the
    /// distinction is the surface that renders (a single-surface takeover, no chrome).
    static let holyGround = SabbathSubtractionPolicy(
        hideFeeds: true,
        hideMetrics: true,
        hideBadges: true,
        hideStreaks: true,
        suppressInAppNotifications: true,
        reduceMotion: true,
        calmPalette: true,
        hideNavigation: true
    )

    /// The canonical policy for a given state. The ONLY place state→removal is decided (I3).
    static func policy(for state: SabbathRhythmState) -> SabbathSubtractionPolicy {
        switch state {
        case .normal:     return .none
        case .rest:       return .rest
        case .presence:   return .presence
        case .holyGround: return .holyGround
        }
    }
}

/// The fields a Selah surface can ask the policy about. Used by the one subtraction
/// modifier so every hide routes through `SabbathSubtractionPolicy` (Invariant I3).
enum SabbathSubtractionField {
    case feeds
    case metrics
    case badges
    case streaks
    case inAppNotifications
    case navigation

    /// Whether this field is removed under the given policy.
    func isRemoved(by policy: SabbathSubtractionPolicy) -> Bool {
        switch self {
        case .feeds:              return policy.hideFeeds
        case .metrics:            return policy.hideMetrics
        case .badges:             return policy.hideBadges
        case .streaks:            return policy.hideStreaks
        case .inAppNotifications: return policy.suppressInAppNotifications
        case .navigation:         return policy.hideNavigation
        }
    }
}

// MARK: - Contract 3: SabbathTriggerSource (spec: TriggerSource)

/// A confidence-gated input that *proposes* a Sabbath state. A trigger never sets
/// state directly — `SabbathTriggerResolver` arbitrates. Sub-threshold confidence
/// must propose `.normal` (stay silent).
protocol SabbathTriggerSource {
    /// Stable identifier for logging / debugging.
    var id: String { get }
    /// Whether this trigger is permitted to fire (its own sub-flag).
    var isEnabled: Bool { get }
    /// The trigger's proposal at `now`. Pure and side-effect free.
    func proposal(now: Date) -> SabbathTriggerProposal
}

/// A single trigger's vote: a proposed state plus a confidence in [0, 1].
struct SabbathTriggerProposal: Equatable {
    let proposedState: SabbathRhythmState
    let confidence: Double

    /// The silent vote — propose nothing.
    static let silent = SabbathTriggerProposal(proposedState: .normal, confidence: 0)
}

// MARK: - Contract 4: SabbathRestSignal (spec: RestSignal)

/// Private, local-only measurement of a rest period. Reflection, not achievement:
/// there is NO score, NO streak, NO comparative or social field, by contract
/// (Guardrail 1 / Invariant I2). Surfaced only at the gentle return, and persisted
/// locally only.
struct SabbathRestSignal: Codable, Equatable {
    /// How long the user remained in a non-`.normal` state, in seconds.
    let timeInState: TimeInterval
    /// Optional private reflection. Never shown to anyone else.
    let reflection: String?
    /// When the rest period closed (local device time). For ordering only — never ranked.
    let closedAt: Date
}

// MARK: - Contract 5: SabbathSafetyInvariant (spec: SafetyInvariant)

/// Encodes Guardrail 2: "Reduce Selah, never the phone." Sabbath Mode quiets only
/// Selah's own feeds/metrics/notifications. It MUST NOT touch OS comms (calls,
/// messages, email), MUST always offer a one-tap guilt-free exit, and MUST NEVER
/// suppress an emergency notification.
enum SabbathSafetyInvariant {

    /// Selah surfaces that are NEVER subtracted, in any Sabbath state. These mirror
    /// the v1 `SABBATH_ALWAYS_ALLOWED` allow-list so the two modules agree.
    static let alwaysAllowed: [String] = [
        "emergency_support",
        "trusted_circle",
        "child_safety_report",
    ]

    /// Sabbath Mode only ever quiets *Selah*. OS-level communication is out of scope
    /// and must remain untouched. This is a contract assertion, not a runtime toggle.
    static let reducesSelahOnly: Bool = true

    /// A one-tap, guilt-free exit (Invariant I1) must exist in every Sabbath state.
    static let exitAlwaysAvailable: Bool = true

    /// Emergency notifications are never suppressed, regardless of policy.
    static let neverSuppressesEmergencies: Bool = true

    /// True if `route` must bypass all subtraction (emergency / safety routes).
    static func isAlwaysAllowed(_ route: String) -> Bool {
        alwaysAllowed.contains(route)
    }

    /// Whether an in-app notification may be suppressed under `policy`. Emergencies
    /// and always-allowed safety routes can NEVER be suppressed (I1 / Guardrail 2).
    static func maySuppressNotification(route: String, policy: SabbathSubtractionPolicy) -> Bool {
        guard !isAlwaysAllowed(route) else { return false }
        return policy.suppressInAppNotifications
    }
}
