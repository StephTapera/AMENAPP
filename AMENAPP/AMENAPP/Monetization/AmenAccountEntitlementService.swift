// AmenAccountEntitlementService.swift
// AMENAPP — Platform Monetization
//
// Singleton service that loads and caches the current user's platform tier
// from Firestore. All access decisions are a display-layer hint only —
// Cloud Functions enforce authoritative entitlement server-side.
//
// Firestore path: users/{uid}/entitlements/platform
// Expected doc field: tier (String matching AmenAccountTier raw values)
// Written: 2026-06-05

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - AmenAccountFeature

/// Platform-level features that can be gated behind a tier check.
enum AmenAccountFeature: String, CaseIterable {
    case liveStreaming           = "liveStreaming"
    case personalDiscoveryAgent = "personalDiscoveryAgent"
    case aiWritingCoach         = "aiWritingCoach"
    case aiMemoryOS             = "aiMemoryOS"
    case bulkAutoRedact         = "bulkAutoRedact"
    case familyGuardianDashboard = "familyGuardianDashboard"
    case aiProducer             = "aiProducer"
    case clipStudio             = "clipStudio"
    case communityModeratorAI   = "communityModeratorAI"
    case impactAnalytics        = "impactAnalytics"
    case liveGiving             = "liveGiving"
}

// MARK: - AmenAccountEntitlementService

@MainActor
final class AmenAccountEntitlementService: ObservableObject {

    // MARK: - Singleton

    static let shared = AmenAccountEntitlementService()

    // MARK: - Published State

    @Published var currentTier: AmenAccountTier = .free
    @Published var isLoading: Bool = false

    // MARK: - Private Cache

    private var cachedAt: Date?
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    // MARK: - Firebase

    private var db = Firestore.firestore()
    private var auth = Auth.auth()
    private var authStateListener: AuthStateDidChangeListenerHandle?

    // MARK: - Init

    private init() {
        authStateListener = auth.addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                if user != nil {
                    await self.loadTier()
                } else {
                    self.currentTier = .free
                    self.cachedAt = nil
                }
            }
        }
    }

    // MARK: - Public API

    /// Loads the current user's platform tier from Firestore.
    /// Falls back to `.free` if the document is missing, malformed, or the
    /// user is unauthenticated.  Caches the result with a 5-minute TTL.
    func loadTier() async {
        guard let uid = auth.currentUser?.uid else {
            currentTier = .free
            cachedAt = Date()
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let docRef = db.collection("users").document(uid)
                .collection("entitlements").document("platform")
            let snapshot = try await docRef.getDocument()

            guard
                let data = snapshot.data(),
                let tierRaw = data["tier"] as? String,
                let tier = AmenAccountTier(rawValue: tierRaw)
            else {
                currentTier = .free
                cachedAt = Date()
                return
            }

            currentTier = tier
            cachedAt = Date()
        } catch {
            // Fail open to free — never block the user on a network error
            currentTier = .free
            cachedAt = Date()
        }
    }

    /// Calls `loadTier()` only if the cached value is older than `cacheTTL`.
    func refreshIfNeeded() async {
        if let cachedAt, Date().timeIntervalSince(cachedAt) < cacheTTL {
            return
        }
        await loadTier()
    }

    /// Forces a cache-busted reload from Firestore.
    func forceRefresh() async {
        cachedAt = nil
        await loadTier()
    }

    // MARK: - Feature Checks

    /// Returns `.eligible` if the current tier includes live streaming,
    /// otherwise `.notEligible(tier:)` with the user's current tier.
    func checkLiveEligibility() -> AmenLiveCapability {
        if currentTier.canGoLive {
            return .eligible
        }
        return .notEligible(tier: currentTier)
    }

    /// Returns `true` if the current tier grants access to the requested feature.
    func hasAccess(to feature: AmenAccountFeature) -> Bool {
        switch feature {
        case .liveStreaming:
            return currentTier.canGoLive
        case .personalDiscoveryAgent:
            return currentTier.canUsePersonalDiscoveryAgent
        case .aiWritingCoach:
            return currentTier.canUseAIWritingCoach
        case .aiMemoryOS:
            return currentTier.canUseAIMemoryOS
        case .bulkAutoRedact:
            return currentTier.canUseBulkAutoRedact
        case .familyGuardianDashboard:
            return currentTier.canUseFamilyGuardianDashboard
        case .aiProducer:
            return currentTier.canUseAIProducer
        case .clipStudio:
            return currentTier.canUseClipStudio
        case .communityModeratorAI:
            return currentTier.canUseCommunityModeratorAI
        case .impactAnalytics:
            return currentTier.canUseImpactAnalytics
        case .liveGiving:
            return currentTier.canUseLiveGiving
        }
    }

    // MARK: - Minimum Tier Requirement

    /// Returns the lowest tier that grants access to the given feature.
    static func minimumTier(for feature: AmenAccountFeature) -> AmenAccountTier {
        switch feature {
        case .liveStreaming:            return .creatorPro
        case .personalDiscoveryAgent:   return .amenPlus
        case .aiWritingCoach:           return .amenPlus
        case .aiMemoryOS:               return .amenPro
        case .bulkAutoRedact:           return .amenPro
        case .familyGuardianDashboard:  return .amenPro
        case .aiProducer:               return .creatorPro
        case .clipStudio:               return .creatorPro
        case .communityModeratorAI:     return .creatorPro
        case .impactAnalytics:          return .creatorPro
        case .liveGiving:               return .churchPro
        }
    }

    // MARK: - Preview Instance

    static let preview: AmenAccountEntitlementService = {
        let service = AmenAccountEntitlementService()
        service.currentTier = .amenPlus
        return service
    }()
}
