// TrustContracts.swift
// AMEN Trust Layer — Frozen Shared Contracts (Phase 0)
// C2PA-aligned capture-chain types. Prefixed with C2PA / Content to
// distinguish from the server-verification types in AccessibilityContracts.swift.

import Foundation

// MARK: - Content Origin State (C2PA capture chain)

/// The origin and edit history of a media item in the C2PA sense.
/// Not to be confused with MediaVerificationState (server-side check result).
enum ContentOriginState: String, Codable {
    case verifiedOriginal   // captured in Amen camera, C2PA manifest signed at capture, intact
    case edited             // crop / color / trim / stabilize — tracked, manifest chained
    case aiAssisted         // AI transcription / translation / summary / a11y enhancement attached
    case aiGenerated        // wholly generated image/video/voice — undiscoverable by default
    case unverified         // imported media, no intact manifest (honest default for outside content)
}

// MARK: - Signer Type

enum SignerType: String, Codable {
    case amenCameraHardwareBacked  // forward slot for when Apple ships native capture signing
    case amenAppSigned             // app signs at capture; key handled off-device / Secure Enclave
    case externalCamera
    case aiTool
    case none
}

// MARK: - Capture Attestation

struct CaptureAttestation: Codable {
    let deviceId: String
    let timestamp: Date
    let bundleVersion: String
    let signatureBase64: String
}

// MARK: - Edit Record (append-only, tamper-evident)

struct EditRecord: Codable {
    let editType: String      // crop, color, trim, stabilize, caption, filter
    let timestamp: Date
    let editorId: String      // user uid
    let description: String
}

// MARK: - AI Contribution Type

enum AIContributionType: String, Codable {
    case transcription
    case translation
    case altText
    case summary
    case chapters
    case caption
    case simplification
    case narration
    case contextNote
    case scriptureDetect
}

// MARK: - C2PA AI Contribution (the audit trail that earns the badge)

struct C2PAAIContribution: Codable {
    let type: AIContributionType
    let model: String
    let jobId: String         // ties to the callable-proxy invocation
    let timestamp: Date
    let humanEdited: Bool     // true once a human revises (Alt Text Editor learning loop)
}

// MARK: - C2PA Media Credential (C2PA-aligned manifest wrapper)

struct C2PAMediaCredential: Codable {
    let mediaId: String
    var originState: ContentOriginState
    let c2paManifestPresent: Bool
    let signerType: SignerType
    let captureAttestation: CaptureAttestation?
    var editChain: [EditRecord]          // append-only
    var aiContributions: [C2PAAIContribution]
    let sourceVerified: Bool
    var metadataIntact: Bool
}

// MARK: - Media Authenticity Score (signals only — NEVER engagement metrics)

struct MediaAuthenticityScore: Codable {
    let originalCapture: Bool
    let provenanceIntact: Bool
    let sourceVerified: Bool
    let metadataIntact: Bool
    let editsDisclosed: Bool
    private(set) var composite: Int   // derived from signals above only; engagement never moves this

    init(originalCapture: Bool,
         provenanceIntact: Bool,
         sourceVerified: Bool,
         metadataIntact: Bool,
         editsDisclosed: Bool) {
        self.originalCapture = originalCapture
        self.provenanceIntact = provenanceIntact
        self.sourceVerified = sourceVerified
        self.metadataIntact = metadataIntact
        self.editsDisclosed = editsDisclosed
        var score = 0
        if originalCapture  { score += 30 }
        if provenanceIntact { score += 25 }
        if sourceVerified   { score += 20 }
        if metadataIntact   { score += 15 }
        if editsDisclosed   { score += 10 }
        self.composite = score
    }
}

// MARK: - Generative Capability (banned list)

enum GenerativeCapabilityKind: String, Codable {
    case faceGeneration
    case voiceCloning
    case deepfakeSermon
    case deepfakeTestimony
    case deepfakePrayer
    case fabricatedConversation
    case fabricatedComment
    case aiTestimonyPosingAsHuman
    case aiPrayerPosingAsHuman
    case defaultAIProfilePhoto
    case aiInfluencerPersona
    case fabricatedDepictionOfRealPerson
}

// MARK: - Policy Gate Result

enum PolicyGateResult {
    case allowed
    case blocked(capability: GenerativeCapabilityKind, assistiveAlternative: String)

    var isBlocked: Bool {
        if case .blocked = self { return true }
        return false
    }
}

// MARK: - Callable Proxy Names

enum TrustA11yCallable: String {
    case a11yTranscribeProxy
    case a11yTranslateProxy
    case a11yAltTextProxy
    case a11ySummarizeProxy
    case a11yChaptersProxy
    case a11yCaptionProxy
    case a11ySimplifyProxy
    case a11yNarrateProxy
    case a11yContextProxy
    case trustVerifyProxy
    case trustDetectSynthetic
    case scriptureResolveProxy
    case registerMediaProvenance
}
