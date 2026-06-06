// AmenChildSafetyModels.swift
// AMENAPP — CommunityOS/ChildSafety
//
// Phase 4 Agent TS-c — Child Safety
//
// Age classification, minor protection capabilities, and the write-once
// age assurance record. Client NEVER writes AgeAssuranceRecord directly —
// it is written exclusively by the Admin SDK via Cloud Functions.
//
// Invariant I-8 (C5 §5): /users/{uid}/private/age_assurance is server-managed only.
// Invariant I-3 (C5 §5): Minor posts default to Private; publicConfirmed required for public.
// C-MINOR-DM (C5 §4b): DMs require mutual follow + guardian approval for minors.
// OPEN-1 (C5 §6): 13 is the current minimum age floor — pending T&S Lead + Legal confirmation.
//
// Phase 4 Agent TS-c
// C5 contract: contracts/C5-security-rules.md §4

import Foundation

// MARK: - AgeCategory

/// Age classification derived from a user's age assurance record.
/// Maps to the `ageTier` Firestore field values used throughout the app.
///
/// OPEN-1 (T&S Lead must resolve before Phase 4 deploy):
///   US COPPA requires parental consent for under-13.
///   EU GDPR-K may require 16 as the minimum in some jurisdictions.
///   Current threshold: 13. T&S Lead + Legal must confirm.
enum AgeCategory: String, Codable, Sendable {
    case underMinimum = "under_minimum"   // Under-13: blocked from app entirely
    case teen         = "teen"            // 13-17 (or 16-17 in EU): restricted experience
    case adult        = "adult"           // 18+: full access
}

// MARK: - MinorProtectionConfig

/// Static capability lists derived from C5 §4c and §4d.
/// These drive client-side enforcement; server-side enforcement is authoritative.
/// Defense in depth: both layers must agree.
enum MinorProtectionConfig {

    // MARK: Blocked capabilities (§4c)

    /// Capabilities that are completely inaccessible to minor accounts.
    /// Mapping to RBAC resource+action pairs from C5 §2.
    static let blockedCapabilities: Set<String> = [
        "sendDM",               // C-MINOR-DM: blocked unless mutual follow + guardian approved
        "viewJobs",             // C-AGE §2l: job listings blocked entirely for minors
        "postPublicly",         // §4a: minor can only post privately by default
        "joinOpenSpaces",       // §2i: minors restricted to church-verified spaces only
        "shareLocation",        // §4c: no location sharing for minors
        "createLiveRoom",       // §4c: no live broadcasting for minors
        "viewAnalytics",        // §4c: no analytics access for minors
        "purchasePremium",      // §4c: no payment/commerce without guardian
        "changeAgeAssurance",   // I-8: cannot self-modify age profile; Admin SDK only
        "viewAdultContent"      // §4c: age-sensitive content blocked (sermons/resources tagged 18+)
    ]

    // MARK: Restricted capabilities (§4d)

    /// Capabilities available to minors but with additional restrictions applied.
    static let restrictedCapabilities: Set<String> = [
        "search",           // §4d: results limited — no adults-only profiles surfaced
        "discover",         // §4d: filtered discovery feed
        "comment",          // §4d: comments go through moderation before appearing
        "joinDiscussion"    // §4d: church/school-verified discussions only
    ]

    // MARK: Defaults enforced on minor accounts (§4a, §4b)

    /// Default privacy level enforced for all minor content. (Invariant I-3)
    static let defaultPrivacyPreset = "private"

    /// Default DM policy enforced for minor accounts. (§4b)
    static let defaultDMPolicy = "mutualFollows"
}

// MARK: - AgeAssuranceRecord

/// The write-once age assurance record stored at /users/{uid}/private/age_assurance.
///
/// CRITICAL — WRITE-ONCE FROM ADMIN SDK:
///   This record is written exclusively by Cloud Functions using the Firebase Admin SDK.
///   No iOS client may write or update this document. The Firestore rule
///   `allow write: if false` on this path is enforced at the server layer.
///   iOS reads this record via AmenChildSafetyService to derive the user's AgeCategory.
///
///   Invariant I-8 (C5 §5): Even ExecutiveAdmin cannot update this via client.
struct AgeAssuranceRecord: Codable, Sendable {
    /// The Firebase Auth UID this record belongs to.
    var userId: String

    /// The resolved age category for this user.
    var ageCategory: AgeCategory

    /// How the age was verified.
    /// Values: "self_reported" | "document_verified" | "guardian_confirmed"
    var verificationMethod: String

    /// Whether the verification has been formally confirmed (vs self-reported only).
    var isVerified: Bool

    /// Optional UID of the linked guardian account. nil until guardian is linked.
    /// Guardian link is established by CF after email verification — never by the minor directly.
    var guardianUserId: String?

    /// When this record was first created (Admin SDK timestamp).
    var createdAt: Date

    /// When the record was formally verified (nil until verification is complete).
    var verifiedAt: Date?
}
