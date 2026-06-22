// EntitlementGate.swift — AMEN Core/Entitlements
// Actor that resolves feature access per the SystemCapability + GateDecision contract.
// Priority: crisisSuppressed → flagOff → subscription → gracePreview → tier compare

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseRemoteConfig
import StoreKit

// MARK: - SystemCapability extensions

extension SystemCapability {
    /// True if the capability sits behind a paywall (isUpsellable drives crisisSuppressed logic).
    var isUpsellable: Bool { requiredTier != .free }

    var requiredTier: Tier {
        switch self {
        case .bereanContextInjection, .verseResonance, .cohortResonance,
             .givingPortfolio, .continuityCrossDevice, .seasonsInsights,
             .matchFeedbackExplained:
            return .premium
        case .volunteerNeedsPosting, .groupFormationAnalytics, .communityHealth:
            return .church
        case .teachingAnalytics:
            return .creator
        default:
            return .free
        }
    }
}

// MARK: - EntitlementGate

/// Thread-safe actor that resolves GateDecision for any SystemCapability.
/// Decisions are cached for 5 minutes to avoid hammering StoreKit / Firestore.
actor EntitlementGate: EntitlementGating {

    static let shared = EntitlementGate()

    // MARK: Cache

    private struct CacheEntry {
        let decision: GateDecision
        let expiresAt: Date
    }

    private var cache: [SystemCapability: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    // MARK: Subscription cache (5-min window)

    private var cachedTier: Tier?
    private var tierCacheExpiresAt: Date = .distantPast

    // MARK: Public API

    func canAccess(_ capability: SystemCapability) async -> GateDecision {
        // Return cached result if still valid
        if let entry = cache[capability], entry.expiresAt > Date() {
            return entry.decision
        }

        let decision = await resolve(capability)
        cache[capability] = CacheEntry(decision: decision, expiresAt: Date().addingTimeInterval(cacheTTL))
        return decision
    }

    /// Call after a subscription purchase or restoration to force re-evaluation.
    func invalidateCache() {
        cache.removeAll()
        cachedTier = nil
        tierCacheExpiresAt = .distantPast
    }

    // MARK: Resolution pipeline

    private func resolve(_ capability: SystemCapability) async -> GateDecision {
        // 1. Crisis suppression — device-only, no network
        let crisisActive = await MainActor.run { CrisisDampening.shared.isActive }
        if crisisActive && capability.isUpsellable {
            return .crisisSuppressed
        }

        // 2. Remote Config flag gate — default true for free capabilities
        let flagKey = "ctx_\(capability.rawValue)_enabled"
        let flagValue: Bool
        let rcValue = RemoteConfig.remoteConfig().configValue(forKey: flagKey)
        // If the key has never been set in Remote Config, .source == .default → treat as true for
        // free capabilities, false for upsellable (safe-off contract).
        if rcValue.source == .static {
            // Never fetched; allow free, gate upsellable
            flagValue = !capability.isUpsellable
        } else {
            flagValue = rcValue.boolValue
        }

        guard flagValue else { return .flagOff }

        // 3. Resolve user's subscription tier (StoreKit 2 + cache)
        let userTier = await resolveSubscriptionTier()

        // 4. Grace preview check (Firestore entitlements/{uid}/previews/{rawValue})
        if let graceDecision = await checkGracePreview(capability: capability) {
            return graceDecision
        }

        // 5. Tier comparison
        let requiredTier = capability.requiredTier
        if tierMeetsRequirement(userTier: userTier, required: requiredTier) {
            return .entitled
        }

        // 6. Access denied — surface the required tier for upsell UI
        return .tierRequired(requiredTier)
    }

    // MARK: Subscription tier resolution

    private func resolveSubscriptionTier() async -> Tier {
        if let cached = cachedTier, tierCacheExpiresAt > Date() {
            return cached
        }

        let tier = await fetchStoreKitTier()
        cachedTier = tier
        tierCacheExpiresAt = Date().addingTimeInterval(cacheTTL)
        return tier
    }

    private func fetchStoreKitTier() async -> Tier {
        // StoreKit 2 — check active subscription status
        // Check in descending privilege order
        for (productId, tier) in [("com.amen.creator", Tier.creator),
                                   ("com.amen.church", Tier.church),
                                   ("com.amen.premium", Tier.premium)] {
            if await hasActiveSubscription(productGroupId: productId) {
                return tier
            }
        }
        return .free
    }

    private func hasActiveSubscription(productGroupId: String) async -> Bool {
        guard let statuses = try? await Product.SubscriptionInfo.status(for: productGroupId) else {
            return false
        }
        return statuses.contains { status in
            switch status.state {
            case .subscribed, .inGracePeriod:
                return true
            default:
                return false
            }
        }
    }

    // MARK: Grace preview

    private func checkGracePreview(capability: SystemCapability) async -> GateDecision? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let db = Firestore.firestore()
        let docRef = db
            .collection("entitlements").document(uid)
            .collection("previews").document(capability.rawValue)

        guard let snap = try? await docRef.getDocument(),
              snap.exists,
              let data = snap.data(),
              let expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue(),
              expiresAt > Date() else {
            return nil
        }

        let remainingDays = max(0, Int(expiresAt.timeIntervalSinceNow / 86_400))
        return .gracePreview(remainingDays: remainingDays)
    }

    // MARK: Tier hierarchy

    private func tierMeetsRequirement(userTier: Tier, required: Tier) -> Bool {
        let hierarchy: [Tier: Int] = [.free: 0, .premium: 1, .church: 2, .creator: 3]
        let userLevel = hierarchy[userTier] ?? 0
        let requiredLevel = hierarchy[required] ?? 0
        return userLevel >= requiredLevel
    }
}
