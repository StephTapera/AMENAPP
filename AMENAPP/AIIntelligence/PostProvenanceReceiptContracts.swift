// PostProvenanceReceiptContracts.swift
// AMENAPP — AIIntelligence
//
// Feature D — Provenance & authenticity labels (post + account precedence).
//
// Swift MIRROR of Backend/functions/src/contracts/postProvenance.ts.
// TypeScript is the source of truth; this file stays shape-aligned field-for-field.
// Do NOT add fields here without adding them to the TS contract first.
//
// Reconciliation with existing runtime types (extend, never duplicate):
//   - AuthenticityKind is MIRRORED from AuthenticityLabel.AuthenticityKind
//     (SocialOSModels.swift). `bridgedKind` maps back to the canonical enum so
//     callers reuse the existing badge/icon machinery rather than forking it.
//   - The post layer derives from TrustAnalysisProfile (PostTrustAnalysisService.swift).
//   - The account layer derives from PassportLevel / TrustPassportService.
//     The Trust Passport stays INTERNAL — no displayed number (D-I2).
//
// INVARIANTS (mirrors postProvenance.test.ts):
//   D-I1  POST precedence: post-level label kind always wins; account tier only
//         raises prominence, never flips the kind.
//   D-I2  Account tier is internal-only; `accountTierWeight` is never displayed.
//   D-I3  Fail-closed: missing post profile OR passport => flat pendingReview.
//   D-I4  Receipt carries basis + sources + coarse band, never a public score.

import Foundation

// MARK: - AuthenticityKind (mirror of AuthenticityLabel.AuthenticityKind raw values)

/// Mirror of `AuthenticityLabel.AuthenticityKind` (SocialOSModels.swift).
/// Raw values are kept identical so `bridgedKind` round-trips losslessly.
enum ProvenanceAuthenticityKind: String, Codable, CaseIterable, Sendable {
    case realMedia              = "real_media"
    case creatorVerified        = "creator_verified"
    case communityVerified      = "community_verified"
    case churchMedia            = "church_media"
    case editedRealFootage      = "edited_real_footage"
    case aiAssistedCaptions     = "ai_assisted_captions"
    case aiAssistedTranslation  = "ai_assisted_translation"
    case transcriptApproved     = "transcript_approved"
    case pendingReview          = "pending_review"
    case syntheticWarning       = "synthetic_warning"

    /// Bridges to the canonical `AuthenticityLabel.AuthenticityKind` by raw value
    /// so existing badge/icon code is reused, not duplicated.
    var bridgedKind: AuthenticityLabel.AuthenticityKind? {
        AuthenticityLabel.AuthenticityKind(rawValue: rawValue)
    }
}

// MARK: - Account tier (mirror of PassportLevel raw values — internal only, D-I2)

enum AccountPassportTier: String, Codable, CaseIterable, Comparable, Sendable {
    case email    = "EMAIL"
    case phone    = "PHONE"
    case identity = "IDENTITY"
    case church   = "CHURCH"
    case leader   = "LEADER"
    case org      = "ORG"

    /// Internal ordering used for prominence only. Never surfaced as a number.
    var order: Int {
        switch self {
        case .email:    return 0
        case .phone:    return 1
        case .identity: return 2
        case .church:   return 3
        case .leader:   return 4
        case .org:      return 5
        }
    }

    static func < (lhs: AccountPassportTier, rhs: AccountPassportTier) -> Bool {
        lhs.order < rhs.order
    }

    /// Bridges from the canonical `PassportLevel` (TrustOSContracts.swift) by raw value.
    init?(passportLevel: PassportLevel) {
        self.init(rawValue: passportLevel.rawValue)
    }
}

// MARK: - Coarse confidence (shape-aligned with AIReceipt ReceiptConfidence)

enum ProvenanceConfidenceBand: String, Codable, Sendable {
    case low, medium, high
}

struct ProvenanceConfidence: Codable, Sendable {
    let band: ProvenanceConfidenceBand
    /// Human-readable basis. REQUIRED, never invented.
    let basis: String
    /// Optional principled internal signal in [0,1]. Omitted when no real signal.
    let score: Double?

    init(band: ProvenanceConfidenceBand, basis: String, score: Double? = nil) {
        self.band = band
        self.basis = basis
        self.score = score
    }
}

// MARK: - Provenance source trail

enum ProvenanceSourceType: String, Codable, Sendable {
    case captureSignal
    case contentCredentials
    case syntheticAnalysis
    case accountTier
    case moderation
}

struct ProvenanceSource: Codable, Sendable {
    let type: ProvenanceSourceType
    /// Real locator: signal id, status string, or tier raw value.
    let locator: String
    /// Human-readable summary, never a raw score.
    let summary: String
}

// MARK: - Label prominence (D-I1: account tier affects prominence ONLY)

enum LabelProminence: String, Codable, Sendable {
    case subtle, standard, elevated
}

struct PostProvenanceLabel: Codable, Sendable {
    let kind: ProvenanceAuthenticityKind
    let title: String
    let detail: String
    /// Coarse only. Never a displayed number.
    let confident: Bool
    /// Account tier may raise prominence; it can NEVER change `kind` (D-I1).
    let prominence: LabelProminence
}

// MARK: - Inputs (the two layers — both intentionally minimal and internal)

/// POST layer. Mirrors the surfaceable parts of `TrustAnalysisProfile`.
struct PostTrustProfile: Codable, Sendable {
    let postId: String
    /// Resolved post-level label kind. POST precedence (D-I1).
    let resolvedKind: ProvenanceAuthenticityKind
    let confidence: ProvenanceConfidence
    /// Whether the post-level analysis is confident (gates label `confident`).
    let confidentSignal: Bool
    let sources: [ProvenanceSource]
}

/// ACCOUNT layer. INTERNAL-only — never a displayed number (D-I2).
struct AccountTrustPassport: Codable, Sendable {
    let uid: String
    let tier: AccountPassportTier
}

// MARK: - PostProvenanceReceipt (resolved output; echoes AIReceipt shape, D-I4)

struct PostProvenanceReceipt: Codable, Sendable {
    let postId: String
    /// The single resolved label. POST precedence over account tier (D-I1).
    let label: PostProvenanceLabel
    let confidence: ProvenanceConfidence
    let sources: [ProvenanceSource]
    /// True when this is the fail-closed flat pendingReview receipt (D-I3).
    let failClosed: Bool
    /// ISO-8601 string.
    let resolvedAt: String
    /// Internal-only tier weight used for prominence. NEVER displayed (D-I2).
    let accountTierWeight: Int
}

// MARK: - Resolver

enum PostProvenanceResolver {

    /// Title/detail copy for each kind. Positive framing; no scores.
    private static func copy(for kind: ProvenanceAuthenticityKind) -> (title: String, detail: String) {
        switch kind {
        case .realMedia:             return ("Real Media", "No synthetic modifications detected.")
        case .creatorVerified:       return ("Captured On Device", "Media was captured directly on the creator's device.")
        case .communityVerified:     return ("Community Verified", "Verified by the community.")
        case .churchMedia:           return ("Church Media", "Published by a verified church.")
        case .editedRealFootage:     return ("AI Edited", "Real footage with AI editing applied.")
        case .aiAssistedCaptions:    return ("AI Assisted", "AI was used for metadata or captions.")
        case .aiAssistedTranslation: return ("AI Translated", "AI was used to translate this content.")
        case .transcriptApproved:    return ("Transcript Ready", "Transcript was reviewed and approved.")
        case .pendingReview:         return ("Pending Review", "Authenticity is being reviewed.")
        case .syntheticWarning:      return ("Synthetic Media", "This media may be synthetically generated.")
        }
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    /// Fail-closed flat receipt (D-I3): a single pendingReview label, never
    /// confident, no positive framing, internal tier weight 0.
    static func failClosedReceipt(postId: String, basis: String) -> PostProvenanceReceipt {
        let c = copy(for: .pendingReview)
        return PostProvenanceReceipt(
            postId: postId,
            label: PostProvenanceLabel(
                kind: .pendingReview,
                title: c.title,
                detail: c.detail,
                confident: false,
                prominence: .subtle
            ),
            confidence: ProvenanceConfidence(band: .low, basis: basis),
            sources: [],
            failClosed: true,
            resolvedAt: isoNow(),
            accountTierWeight: 0
        )
    }

    /// Prominence derivation — account tier affects PROMINENCE ONLY (D-I1).
    static func prominence(for tier: AccountPassportTier) -> LabelProminence {
        if tier.order >= AccountPassportTier.identity.order { return .elevated }
        if tier.order >= AccountPassportTier.phone.order { return .standard }
        return .subtle
    }

    /// Pure resolver. POST precedence over account tier (D-I1); fail-closed when
    /// either layer is absent (D-I3); never a public score (D-I2/D-I4).
    static func resolvePostLabels(
        profile: PostTrustProfile?,
        passport: AccountTrustPassport?
    ) -> PostProvenanceReceipt {
        // D-I3: missing the account passport -> flat fail-closed receipt.
        guard let passport else {
            return failClosedReceipt(postId: profile?.postId ?? "", basis: "account passport unavailable")
        }
        // D-I3: missing the post analysis -> flat fail-closed receipt.
        guard let profile else {
            return failClosedReceipt(postId: "", basis: "post analysis unavailable")
        }

        let c = copy(for: profile.resolvedKind)
        // D-I1: account tier influences prominence ONLY; never the kind.
        let prom = prominence(for: passport.tier)

        let sources: [ProvenanceSource] = profile.sources + [
            ProvenanceSource(
                type: .accountTier,
                locator: passport.tier.rawValue,
                summary: "Account verification affects label prominence only."
            )
        ]

        return PostProvenanceReceipt(
            postId: profile.postId,
            label: PostProvenanceLabel(
                kind: profile.resolvedKind, // POST precedence (D-I1)
                title: c.title,
                detail: c.detail,
                confident: profile.confidentSignal,
                prominence: prom
            ),
            confidence: profile.confidence,
            sources: sources,
            failClosed: false,
            resolvedAt: isoNow(),
            // D-I2: internal-only weight, never displayed.
            accountTierWeight: passport.tier.order
        )
    }
}
