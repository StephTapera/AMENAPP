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

// MARK: - BereanConstitutionalConfig

struct BereanConstitutionalConfig: Codable, Equatable {
    let version: String
    let antiHallucinationRules: [BereanAntiHallucinationRule]
    let confidenceThresholds: BereanConfidenceThresholds
    let highRiskTopics: [String]
    let modeSettings: [String: BereanModeConfig]
    let scriptureVerificationRequired: Bool
    let theologyNeutralityRequired: Bool

    // MARK: Shared default — matches DEFAULT_CONSTITUTION seed

    static let shared = BereanConstitutionalConfig(
        version: "1.0.0",
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
        theologyNeutralityRequired: true
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
}
