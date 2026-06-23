import Foundation

// MARK: - BereanConstitutionalConfig
//
// Swift mirror of the Backend constitutionalConfig.ts `ConstitutionalConfig`
// interface. Used by iOS-side Berean consumers to perform lightweight local
// checks (high-risk topic guard, mode verification requirement) without a
// round-trip to Cloud Functions.
//
// The in-process `shared` instance matches the DEFAULT_CONSTITUTION seed.
// A refreshed copy can be fetched via `BereanConstitutionalConfigLoader`
// (reads the Firestore `berean_constitution/v1` document) and then stored
// in the singleton at app launch.
//
// Wire shape must stay in sync with:
//   Backend/functions/src/berean/constitutionalConfig.ts
//   functions/berean-constitution-v1.json

// MARK: - ModeConfig

struct BereanModeConfig: Codable, Equatable {
    let requireVerification: Bool
    let maxRetries: Int
    let degradeOnFailure: Bool
    let allowCreativeLatitude: Bool
}

// MARK: - ConfidenceThresholds

struct BereanConfidenceThresholds: Codable, Equatable {
    let high: Double
    let moderate: Double
    let low: Double
}

// MARK: - AntiHallucinationRule

struct BereanAntiHallucinationRule: Codable, Identifiable, Equatable {
    let id: String
    let description: String
    let severity: BereanRuleSeverity
}

enum BereanRuleSeverity: String, Codable {
    case critical
    case high
    case medium
}

// MARK: - Governance delta articles (Wave 1: invariants 3, 4, 8)

/// Invariant 3 — The Companion Boundary (parasocial / idolatry guard).
struct BereanCompanionBoundary: Codable, Equatable {
    let noMediator: String
    let noAuthority: String
    let noDevotion: String
    let noDependence: String
    let defaultReflex: String
    let prohibitedPhrases: [String]
}

/// Invariant 4 — a single non-overridable red line.
struct BereanRedLine: Codable, Identifiable, Equatable {
    let id: String
    let description: String
    /// Always false — present so the wire shape matches the TS `overridable: false`.
    let overridable: Bool
}

/// Invariant 8 — an immutable, change-controlled founder ruling.
struct BereanFounderRuling: Codable, Identifiable, Equatable {
    let id: String
    let ruling: String
    let codifiedAtISO: String
    let immutable: Bool
}

// MARK: - BereanConstitutionalConfig

struct BereanConstitutionalConfig: Codable, Equatable {
    let version: String
    let antiHallucinationRules: [BereanAntiHallucinationRule]
    let confidenceThresholds: BereanConfidenceThresholds
    let highRiskTopics: [String]
    let modeSettings: [String: BereanModeConfig]
    let scriptureVerificationRequired: Bool
    let theologyNeutralityRequired: Bool
    // Governance delta articles — optional so old Firestore docs decode cleanly.
    let companionBoundary: BereanCompanionBoundary?
    let redLines: [BereanRedLine]?
    let founderRulings: [BereanFounderRuling]?

    // MARK: Shared default — matches DEFAULT_CONSTITUTION seed

    static let shared = BereanConstitutionalConfig(
        version: "1.1.0",
        antiHallucinationRules: [
            BereanAntiHallucinationRule(
                id: "NO_FABRICATED_VERSES",
                description: "Never quote scripture not in evidence chunks",
                severity: .critical
            ),
            BereanAntiHallucinationRule(
                id: "NO_INVENTED_SOURCES",
                description: "Never cite theologians, studies, or stats not in evidence",
                severity: .critical
            ),
            BereanAntiHallucinationRule(
                id: "DECLARE_ASSUMPTIONS",
                description: "All assumptions explicitly stated",
                severity: .high
            ),
            BereanAntiHallucinationRule(
                id: "CALIBRATED_CONFIDENCE",
                description: "Confidence must reflect evidence quality",
                severity: .high
            ),
            BereanAntiHallucinationRule(
                id: "NO_FALSE_CONSENSUS",
                description: "Contested theological questions must present multiple views",
                severity: .medium
            ),
        ],
        confidenceThresholds: BereanConfidenceThresholds(high: 0.85, moderate: 0.65, low: 0.40),
        highRiskTopics: [
            "theology",
            "counseling",
            "medical",
            "legal",
            "financial",
            "church_governance",
            "abuse",
        ],
        modeSettings: [
            "Ask": BereanModeConfig(
                requireVerification: true, maxRetries: 2,
                degradeOnFailure: true, allowCreativeLatitude: false
            ),
            "Discern": BereanModeConfig(
                requireVerification: true, maxRetries: 2,
                degradeOnFailure: true, allowCreativeLatitude: false
            ),
            "Build": BereanModeConfig(
                requireVerification: true, maxRetries: 2,
                degradeOnFailure: true, allowCreativeLatitude: true
            ),
            "Guard": BereanModeConfig(
                requireVerification: true, maxRetries: 0,
                degradeOnFailure: true, allowCreativeLatitude: false
            ),
            "Reflect": BereanModeConfig(
                requireVerification: true, maxRetries: 2,
                degradeOnFailure: true, allowCreativeLatitude: false
            ),
        ],
        scriptureVerificationRequired: true,
        theologyNeutralityRequired: true,
        companionBoundary: BereanCompanionBoundary(
            noMediator: "Berean never positions itself as a mediator between the user and God.",
            noAuthority: "Berean never claims spiritual or ecclesial authority and never issues binding rulings.",
            noDevotion: "Berean never accepts worship, devotion, prayer addressed to itself, or confession-as-absolution.",
            noDependence: "Berean never encourages dependence on itself in place of Scripture, prayer, or community.",
            defaultReflex: "Under spiritual weight or crisis, Berean hands the user OUTWARD — to God, church, pastor, trusted believers.",
            prohibitedPhrases: [
                "keep talking to me",
                "you can always come to me",
                "i'm always here for you",
                "you don't need anyone else",
                "talk to me instead",
                "confess to me",
                "pray to me",
            ]
        ),
        redLines: [
            BereanRedLine(id: "spiritual_surveillance", description: "No monitoring/profiling of spiritual performance for ranking, nudging, or disclosure.", overridable: false),
            BereanRedLine(id: "spiritual_scoring", description: "No metric ranking users by piety, growth, or faithfulness.", overridable: false),
            BereanRedLine(id: "ecclesial_impersonation", description: "Never speak AS a church, pastor, or spiritual authority; no binding rulings.", overridable: false),
            BereanRedLine(id: "csam", description: "csam_hash_scan_enabled stays OFF until the four-part federal gate is satisfied.", overridable: false),
            BereanRedLine(id: "minor_sexualization", description: "No content sexualizing minors or facilitating grooming, ever.", overridable: false),
            BereanRedLine(id: "crisis_data_export", description: "Crisis-path data never exported to analytics or model-training pipelines.", overridable: false),
            BereanRedLine(id: "crisis_data_unencrypted", description: "Crisis-path data encrypted at rest; fails closed if encryption cannot be verified.", overridable: false),
        ],
        founderRulings: [
            BereanFounderRuling(id: "FR-1-NO-SPIRITUAL-SURVEILLANCE", ruling: "Behavioral spiritual data is never logged-for-scoring or profiled.", codifiedAtISO: "2026-06-20T00:00:00Z", immutable: true),
            BereanFounderRuling(id: "FR-2-NO-SPIRITUAL-SCORING", ruling: "No piety/growth/faithfulness ranking is computed or rendered.", codifiedAtISO: "2026-06-20T00:00:00Z", immutable: true),
            BereanFounderRuling(id: "FR-3-CRISIS-DATA-SACRED", ruling: "Crisis-path data encrypted at rest, never exported to analytics/training, fail-closed.", codifiedAtISO: "2026-06-20T00:00:00Z", immutable: true),
            BereanFounderRuling(id: "FR-4-FORMATION-OVER-ENGAGEMENT", ruling: "No ranking/notification/feature designed to maximize session length, DAU, retention, or re-engagement.", codifiedAtISO: "2026-06-20T00:00:00Z", immutable: true),
        ]
    )

    // MARK: Convenience helpers

    /// Returns true when the given intent label is in highRiskTopics.
    /// Comparison is case-insensitive.
    func isHighRiskTopic(_ intent: String) -> Bool {
        highRiskTopics.contains(intent.lowercased())
    }

    /// Returns true when the mode requires server-side verification.
    /// Defaults to true (fail-closed) when the mode key is not found.
    func requiresVerification(mode: String) -> Bool {
        modeSettings[mode]?.requireVerification ?? true
    }

    /// Returns the maxRetries for a given mode.
    /// Defaults to 0 (no retries — fail-closed) when mode is not found.
    func maxRetries(mode: String) -> Int {
        modeSettings[mode]?.maxRetries ?? 0
    }

    /// Returns true when the mode should degrade the response on failure
    /// rather than surfacing an error to the user.
    func degradesOnFailure(mode: String) -> Bool {
        modeSettings[mode]?.degradeOnFailure ?? true
    }

    /// Returns the confidence tier label for a given numeric score.
    func confidenceTier(for score: Double) -> String {
        if score >= confidenceThresholds.high { return "high" }
        if score >= confidenceThresholds.moderate { return "moderate" }
        return "low"
    }

    /// Returns all critical anti-hallucination rule IDs.
    var criticalRuleIDs: [String] {
        antiHallucinationRules
            .filter { $0.severity == .critical }
            .map { $0.id }
    }

    // MARK: Governance delta helpers (invariants 3, 4, 8)

    /// Invariant 3 — returns true when `text` contains a phrase that would make
    /// Berean the terminus of the user's spiritual life ("keep talking to me",
    /// etc.). Fail-closed: if the boundary article is missing, treat any of the
    /// canonical prohibited phrases as violations.
    func violatesCompanionBoundary(_ text: String) -> Bool {
        let haystack = text.lowercased()
        let phrases = companionBoundary?.prohibitedPhrases ?? [
            "keep talking to me", "talk to me instead", "confess to me", "pray to me",
        ]
        return phrases.contains { haystack.contains($0) }
    }

    /// Invariant 4 — the set of codified red-line IDs. Fail-closed default is the
    /// full canonical set so a stale decode never drops a red line.
    var redLineIDs: [String] {
        (redLines ?? []).map { $0.id }
    }

    /// Invariant 8 — founder rulings are immutable; this surfaces any decode that
    /// arrived with `immutable == false` (a tamper signal the caller should reject).
    var tamperedFounderRulings: [BereanFounderRuling] {
        (founderRulings ?? []).filter { !$0.immutable }
    }
}
