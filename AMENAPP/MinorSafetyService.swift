//
//  MinorSafetyService.swift
//  AMENAPP
//
//  Hard safety defaults for minors and age-unknown accounts.
//  All DM and media policies pass through this service before any send is allowed.
//
//  Design principles:
//  - Age-unknown = treated as minor until verified
//  - Defaults are restrictive; users unlock features by verifying age
//  - No "kids mode" required — this is the baseline for everyone
//  - Guardian settings are optional add-ons, not the primary protection
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Age Verification Status

enum AgeVerificationStatus: String, Codable {
    case unknown            // Default for all new accounts — treated as minor
    case selfDeclaredAdult  // User claimed 18+, not verified
    case verifiedAdult      // Phone/ID verified adult
    case confirmedMinor     // Under 18 — confirmed or inferred
    case parentalConsent    // Minor with guardian consent on file
}

// MARK: - Trust Tier (extends account age tiers)

/// Full trust tier that combines account age + verification status.
/// This is the authoritative trust level used across all safety decisions.
enum UserTrustTier: Int, Codable, Comparable {
    case blocked        = 0  // Account suspended/frozen — no sends
    case restricted     = 1  // Under restriction: limited DMs, no media, no links
    case newAccount     = 2  // 0-2 days, not yet trusted
    case infant         = 3  // 3-6 days
    case young          = 4  // 7-13 days
    case established    = 5  // 14-29 days
    case mature         = 6  // 30+ days
    case verified       = 7  // Phone or email verified
    case trusted        = 8  // Verified + positive community signals + no strikes

    static func < (lhs: UserTrustTier, rhs: UserTrustTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Minor Safety Policy

/// The computed policy for a specific send attempt between two users.
/// Produced by MinorSafetyService and consumed by the messaging pipeline.
struct MinorSafetyPolicy {
    let canSendDM: Bool
    let canSendMedia: Bool
    let canSendLinks: Bool
    let canShareContactInfo: Bool
    let riskThresholdMultiplier: Double  // < 1.0 = lower thresholds for minors
    let blockReason: String?

    /// Policy applied when sender is unknown/unverified
    static let defaultUnverified = MinorSafetyPolicy(
        canSendDM: false,
        canSendMedia: false,
        canSendLinks: false,
        canShareContactInfo: false,
        riskThresholdMultiplier: 0.5,  // Half the normal threshold to trigger holds/blocks
        blockReason: "Verify your account to send messages"
    )

    /// Policy for confirmed minor → minor (same-age band)
    static let minorToMinorSameBand = MinorSafetyPolicy(
        canSendDM: true,
        canSendMedia: false,  // No media between minors by default
        canSendLinks: false,
        canShareContactInfo: false,
        riskThresholdMultiplier: 0.4,
        blockReason: nil
    )

    /// Policy for confirmed adult → confirmed minor (cross-age)
    static let adultToMinor = MinorSafetyPolicy(
        canSendDM: false,
        canSendMedia: false,
        canSendLinks: false,
        canShareContactInfo: false,
        riskThresholdMultiplier: 0.3,  // Very aggressive detection
        blockReason: "Adults cannot send direct messages to minors without mutual connection approval"
    )

    /// Policy for verified mutual connections (same age band, no strikes)
    static let mutualTrusted = MinorSafetyPolicy(
        canSendDM: true,
        canSendMedia: true,
        canSendLinks: true,
        canShareContactInfo: false,  // Still no contact info even between trusted users
        riskThresholdMultiplier: 1.0,
        blockReason: nil
    )

    /// Full policy for verified adults with no restrictions
    static let fullAccess = MinorSafetyPolicy(
        canSendDM: true,
        canSendMedia: true,
        canSendLinks: true,
        canShareContactInfo: true,
        riskThresholdMultiplier: 1.0,
        blockReason: nil
    )
}

// MARK: - Minor Safety Service

@MainActor
final class MinorSafetyService {
    static let shared = MinorSafetyService()

    private let db = Firestore.firestore()
    private var userProfileCache: [String: UserSafetyProfile] = [:]

    private init() {}

    // MARK: - User Safety Profile

    /// Lightweight safety profile loaded for a user.
    /// Cached in memory; refreshed when staleness threshold exceeded.
    struct UserSafetyProfile {
        let userId: String
        let ageVerificationStatus: AgeVerificationStatus
        let trustTier: UserTrustTier
        let birthYear: Int?           // nil = not provided
        let hasVerifiedPhone: Bool
        let hasVerifiedEmail: Bool
        let strikeCount: Int
        let isFrozen: Bool
        let guardianOptIn: Bool       // Guardian has opted in to additional controls
        let fetchedAt: Date

        var estimatedAge: Int? {
            guard let year = birthYear else { return nil }
            return Calendar.current.component(.year, from: Date()) - year
        }

        var isMinorOrUnknown: Bool {
            switch ageVerificationStatus {
            case .unknown, .confirmedMinor: return true
            case .selfDeclaredAdult: return estimatedAge.map { $0 < 18 } ?? true
            case .verifiedAdult, .parentalConsent: return false
            }
        }

        var isStale: Bool {
            Date().timeIntervalSince(fetchedAt) > 300  // 5 minute cache
        }
    }

    // MARK: - Primary Policy Resolution

    /// Compute the DM safety policy for a send attempt.
    /// Call this before MessageSafetyGateway.evaluate() so the gateway can apply
    /// the correct risk threshold multiplier.
    ///
    /// Returns a policy struct that specifies what is and isn't allowed.
    func resolvePolicy(
        senderId: String,
        recipientId: String,
        hasMutualFollow: Bool,
        messageContainsMedia: Bool,
        messageContainsLink: Bool
    ) async -> MinorSafetyPolicy {
        guard !senderId.isEmpty, !recipientId.isEmpty else {
            return .defaultUnverified
        }

        let (sender, recipient) = await withTaskGroup(
            of: (Bool, UserSafetyProfile?).self
        ) { group -> (UserSafetyProfile, UserSafetyProfile) in
            var senderProfile: UserSafetyProfile?
            var recipientProfile: UserSafetyProfile?

            group.addTask { [weak self] in
                let profile = await self?.fetchProfile(userId: senderId)
                return (true, profile)
            }
            group.addTask { [weak self] in
                let profile = await self?.fetchProfile(userId: recipientId)
                return (false, profile)
            }

            for await (isTheSender, profile) in group {
                if isTheSender { senderProfile = profile }
                else { recipientProfile = profile }
            }

            let senderFallback = UserSafetyProfile(
                userId: senderId,
                ageVerificationStatus: .unknown,
                trustTier: .newAccount,
                birthYear: nil,
                hasVerifiedPhone: false,
                hasVerifiedEmail: false,
                strikeCount: 0,
                isFrozen: false,
                guardianOptIn: false,
                fetchedAt: Date()
            )
            let recipientFallback = UserSafetyProfile(
                userId: recipientId,
                ageVerificationStatus: .unknown,
                trustTier: .newAccount,
                birthYear: nil,
                hasVerifiedPhone: false,
                hasVerifiedEmail: false,
                strikeCount: 0,
                isFrozen: false,
                guardianOptIn: false,
                fetchedAt: Date()
            )

            return (senderProfile ?? senderFallback, recipientProfile ?? recipientFallback)
        }

        // Frozen sender = hard block
        if sender.isFrozen {
            return MinorSafetyPolicy(
                canSendDM: false, canSendMedia: false,
                canSendLinks: false, canShareContactInfo: false,
                riskThresholdMultiplier: 0.0,
                blockReason: "Your account is currently restricted"
            )
        }

        // Cross-age protection: adult → minor
        let senderIsAdult = !sender.isMinorOrUnknown
        let recipientIsMinor = recipient.isMinorOrUnknown

        if senderIsAdult && recipientIsMinor {
            // Even mutual follows don't unlock adult → minor DMs by default
            // Only parentalConsent + mutual follow can unlock this
            if recipient.ageVerificationStatus == .parentalConsent && hasMutualFollow {
                return MinorSafetyPolicy(
                    canSendDM: true,
                    canSendMedia: false,
                    canSendLinks: false,
                    canShareContactInfo: false,
                    riskThresholdMultiplier: 0.35,
                    blockReason: nil
                )
            }
            return .adultToMinor
        }

        // Both unknown/minor: allow DMs but restrict media/links regardless of follow status
        if sender.isMinorOrUnknown && recipient.isMinorOrUnknown {
            if false {
                // Kept for structural parity — mutual-follow gate removed per product requirement
                return MinorSafetyPolicy(
                    canSendDM: false, canSendMedia: false,
                    canSendLinks: false, canShareContactInfo: false,
                    riskThresholdMultiplier: 0.4,
                    blockReason: nil
                )
            }

            // Age band check: only same-ish ages (within 3 years)
            if let senderAge = sender.estimatedAge, let recipientAge = recipient.estimatedAge {
                let ageDifference = abs(senderAge - recipientAge)
                if ageDifference > 3 {
                    return .adultToMinor
                }
            }
            return .minorToMinorSameBand
        }

        // Both adults (or verified adults)
        if hasMutualFollow && sender.trustTier >= .established && sender.strikeCount == 0 {
            return .fullAccess
        }

        if hasMutualFollow {
            return .mutualTrusted
        }

        // Strangers: new account restrictions from NewAccountRestrictionService apply
        // Media and links blocked for non-mutuals regardless of age
        return MinorSafetyPolicy(
            canSendDM: sender.trustTier >= .infant,
            canSendMedia: false,
            canSendLinks: false,
            canShareContactInfo: false,
            riskThresholdMultiplier: sender.trustTier >= .established ? 0.8 : 0.6,
            blockReason: sender.trustTier < .infant
                ? "New accounts must wait before messaging users they don't follow"
                : nil
        )
    }

    // MARK: - Profile Fetch

    func fetchProfile(userId: String) async -> UserSafetyProfile? {
        // Return from cache if fresh
        if let cached = userProfileCache[userId], !cached.isStale {
            return cached
        }

        do {
            // Fetch from users collection and userSafetyRecords in parallel
            async let userDoc = db.collection("users").document(userId).getDocument()
            async let safetyDoc = db.collection("userSafetyRecords").document(userId).getDocument()

            let (user, safety) = try await (userDoc, safetyDoc)

            let userData = user.data() ?? [:]
            let safetyData = safety.data() ?? [:]

            // Parse age verification
            let statusRaw = userData["ageVerificationStatus"] as? String ?? "unknown"
            let ageStatus = AgeVerificationStatus(rawValue: statusRaw) ?? .unknown

            // Parse trust tier from safety record or compute from account age
            let tierRaw = safetyData["trustTier"] as? Int
            let trustTier: UserTrustTier
            if let raw = tierRaw, let tier = UserTrustTier(rawValue: raw) {
                trustTier = tier
            } else {
                // Compute from account age (createdAt field)
                let createdAt = (userData["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                trustTier = computeTrustTier(from: createdAt, userData: userData)
            }

            let profile = UserSafetyProfile(
                userId: userId,
                ageVerificationStatus: ageStatus,
                trustTier: trustTier,
                birthYear: userData["birthYear"] as? Int,
                hasVerifiedPhone: userData["phoneVerified"] as? Bool ?? false,
                hasVerifiedEmail: userData["emailVerified"] as? Bool ?? false,
                strikeCount: safetyData["strikes"] as? Int ?? 0,
                isFrozen: (safetyData["accountStatus"] as? String) == "frozen",
                guardianOptIn: userData["guardianOptIn"] as? Bool ?? false,
                fetchedAt: Date()
            )

            userProfileCache[userId] = profile
            return profile
        } catch {
            return nil
        }
    }

    // MARK: - Trust Tier Computation

    private func computeTrustTier(from createdAt: Date, userData: [String: Any]) -> UserTrustTier {
        let daysSinceCreation = Calendar.current.dateComponents(
            [.day], from: createdAt, to: Date()
        ).day ?? 0

        let hasPhone = userData["phoneVerified"] as? Bool ?? false
        let hasEmail = userData["emailVerified"] as? Bool ?? false

        // Verification boosts tier
        if hasPhone && daysSinceCreation >= 30 {
            return .trusted
        }
        if hasPhone || hasEmail {
            return .verified
        }

        switch daysSinceCreation {
        case 0...2:   return .newAccount
        case 3...6:   return .infant
        case 7...13:  return .young
        case 14...29: return .established
        default:      return .mature
        }
    }

    // MARK: - Minor Flag for Safety Gateway

    /// Returns true if recipient should be treated as a minor (more aggressive detection).
    func recipientIsMinorOrUnknown(_ recipientId: String) async -> Bool {
        let profile = await fetchProfile(userId: recipientId)
        return profile?.isMinorOrUnknown ?? true  // Default to minor-safe if unknown
    }

    /// Returns the risk threshold multiplier for a given recipient.
    /// MessageSafetyGateway multiplies its signal weights by this value.
    func riskMultiplier(for recipientId: String) async -> Double {
        let profile = await fetchProfile(userId: recipientId)
        guard let p = profile else { return 0.5 }  // Conservative default
        if p.isMinorOrUnknown { return 0.35 }
        if p.guardianOptIn { return 0.40 }
        return 1.0
    }

    // MARK: - Evidence Preservation (Freeze = No Deletes)

    /// Called when an account is frozen. Sets a Firestore flag that prevents
    /// message deletion. Firestore rules enforce this server-side.
    func preserveEvidenceForFrozenAccount(_ userId: String) async {
        guard !userId.isEmpty else { return }
        do {
            try await db.collection("userSafetyRecords").document(userId).setData(
                [
                    "evidencePreservationActive": true,
                    "evidencePreservedAt": FieldValue.serverTimestamp(),
                    "canDeleteMessages": false,
                    "canChangeUsername": false,
                    "canChangeProfilePhoto": false
                ],
                merge: true
            )
        } catch {
            dlog("⚠️ [MinorSafety] Failed to set evidence preservation: \(error)")
        }
    }

    // MARK: - Guardian Settings

    /// Records that a guardian has opted in to additional controls for a minor.
    func setGuardianOptIn(minorUserId: String, guardianUserId: String, enabled: Bool) async {
        guard !minorUserId.isEmpty else { return }
        do {
            try await db.collection("users").document(minorUserId).setData(
                [
                    "guardianOptIn": enabled,
                    "guardianUserId": enabled ? guardianUserId : NSNull(),
                    "guardianOptInUpdatedAt": FieldValue.serverTimestamp()
                ],
                merge: true
            )
            // Invalidate cache
            userProfileCache.removeValue(forKey: minorUserId)
        } catch {
            dlog("⚠️ [MinorSafety] Failed to update guardian settings: \(error)")
        }
    }

    // MARK: - Cache Management

    func invalidateCache(for userId: String) {
        userProfileCache.removeValue(forKey: userId)
    }

    func clearCache() {
        userProfileCache.removeAll()
    }
}

// MARK: - UserTrustTier extension

extension UserTrustTier {
    /// Returns true if this tier permits sending direct messages (not frozen/blocked).
    var canInitiateDM: Bool {
        return self >= .infant
    }
}
