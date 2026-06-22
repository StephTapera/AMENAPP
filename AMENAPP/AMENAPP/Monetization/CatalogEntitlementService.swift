// CatalogEntitlementService.swift
// AMENAPP — Catalog + Knowledge Network Monetization
//
// DISPLAY-ONLY hint layer for catalog entitlements.
// The authoritative gate is always server-side (checkCatalogEntitlement CF).
//
// Firestore path: users/{uid}/entitlements/platform
// Expected doc field: tier (String matching CatalogTier raw values)
//
// Tier model:
//   free            — catalog_read only
//   creator_pro     — + askCreator, catalogCreate; 500-work limit
//   creator_studio  — + knowledgeMap, unlimitedWorks, transcriptSearch
//   organization    — all creator_studio + org-level access
//
// Deep-links (Spotify, Apple Music, YouTube, Amazon product pages) are
// ALWAYS accessible to all users — only intelligence features are gated.
//
// Written: 2026-06-06

import SwiftUI
import FirebaseFirestore

// MARK: - CatalogFeature

/// Features that can be gated in the Catalog + Knowledge Network.
/// This enum is used for display-hint checks only.
enum CatalogFeature {
    /// Reading catalog content — always free.
    case catalogRead
    /// "Ask This Creator" AI question flow — Creator Pro+.
    case askCreator
    /// Knowledge Map visualization — Creator Studio+.
    case knowledgeMap
    /// Building / publishing a catalog — Creator Pro+.
    case catalogCreate
    /// Unlimited published works — Creator Studio+. (Creator Pro capped at 500.)
    case unlimitedWorks
    /// Full-text transcript search across works — Creator Studio+.
    case transcriptSearch
}

// MARK: - CatalogTier

/// Matches the `tier` field written by catalogEntitlements.js (server-side).
enum CatalogTier: String {
    case free
    case creatorPro     = "creator_pro"
    case creatorStudio  = "creator_studio"
    case organization
}

// MARK: - CatalogEntitlementService

/// Singleton that provides DISPLAY-ONLY hints about the current user's
/// catalog entitlement tier. Call `load(userId:)` once after sign-in.
///
/// - Important: Never use `canAccess(_:)` as the final authority for
///   blocking access. Real gates live in the `checkCatalogEntitlement`
///   Cloud Function and signed-URL delivery.
@MainActor
final class CatalogEntitlementService: ObservableObject {

    // MARK: - Singleton

    static let shared = CatalogEntitlementService()

    // MARK: - Published State

    /// Current catalog tier (display hint only).
    @Published private(set) var tier: CatalogTier = .free
    /// True after the first successful or failed Firestore fetch.
    @Published private(set) var isLoaded = false

    // MARK: - Cache

    private var lastFetched: Date?
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    // MARK: - Init

    private init() {}

    // MARK: - Load

    /// Loads (or refreshes) the catalog tier from Firestore.
    /// Uses a 5-minute cache; call `invalidate()` to force a reload.
    /// Fails closed — defaults to `.free` on any error.
    func load(userId: String) async {
        // Return cached value within TTL
        if let fetched = lastFetched,
           Date().timeIntervalSince(fetched) < cacheTTL,
           isLoaded {
            return
        }

        do {
            let doc = try await Firestore.firestore()
                .collection("users").document(userId)
                .collection("entitlements").document("platform")
                .getDocument()

            if let raw = doc.data()?["tier"] as? String,
               let parsed = CatalogTier(rawValue: raw) {
                self.tier = parsed
            } else {
                // Document exists but tier unrecognized — treat as free
                self.tier = .free
            }
        } catch {
            // Fail closed — assume free if Firestore is unreachable
            self.tier = .free
        }

        self.isLoaded = true
        self.lastFetched = Date()
    }

    /// Clears the cache so the next `load(userId:)` call hits Firestore.
    func invalidate() {
        lastFetched = nil
        isLoaded = false
    }

    // MARK: - Display Hints

    /// Returns a display hint indicating whether the current tier includes
    /// the requested feature. Server enforces the real gate.
    func canAccess(_ feature: CatalogFeature) -> Bool {
        switch feature {
        case .catalogRead:
            // Free to all — deep-links and reading are never gated
            return true

        case .askCreator:
            return tier == .creatorPro || tier == .creatorStudio || tier == .organization

        case .knowledgeMap:
            return tier == .creatorStudio || tier == .organization

        case .catalogCreate:
            return tier == .creatorPro || tier == .creatorStudio || tier == .organization

        case .unlimitedWorks:
            return tier == .creatorStudio || tier == .organization

        case .transcriptSearch:
            return tier == .creatorStudio || tier == .organization
        }
    }

    /// The minimum tier required to access a feature (used by paywall UI).
    static func minimumTier(for feature: CatalogFeature) -> CatalogTier {
        switch feature {
        case .catalogRead:      return .free
        case .askCreator:       return .creatorPro
        case .catalogCreate:    return .creatorPro
        case .knowledgeMap:     return .creatorStudio
        case .unlimitedWorks:   return .creatorStudio
        case .transcriptSearch: return .creatorStudio
        }
    }

    // MARK: - Upgrade Prompts

    /// Returns a user-facing upgrade prompt for locked features.
    func upgradePrompt(for feature: CatalogFeature) -> String {
        switch feature {
        case .catalogRead:
            return "" // Always accessible; no upgrade needed
        case .askCreator:
            return "Upgrade to Creator Pro to unlock Ask This Creator"
        case .knowledgeMap:
            return "Upgrade to Creator Studio to access the Knowledge Map"
        case .catalogCreate:
            return "Upgrade to Creator Pro to build and publish your catalog"
        case .unlimitedWorks:
            return "Upgrade to Creator Studio for unlimited published works"
        case .transcriptSearch:
            return "Upgrade to Creator Studio for full-text transcript search"
        }
    }

    /// Returns a localized display name for a tier (for UI labels).
    static func displayName(for tier: CatalogTier) -> String {
        switch tier {
        case .free:           return "Free"
        case .creatorPro:     return "Creator Pro"
        case .creatorStudio:  return "Creator Studio"
        case .organization:   return "Organization"
        }
    }

    /// StoreKit product ID for self-serve upgrade (Organization is custom/enterprise).
    static func storeKitProductID(for tier: CatalogTier) -> String? {
        switch tier {
        case .free:           return nil
        case .creatorPro:     return "com.amenapp.subscription.catalog.creatorpro.monthly"
        case .creatorStudio:  return "com.amenapp.subscription.catalog.creatorstudio.monthly"
        case .organization:   return nil // Custom — handled via Stripe checkout or sales
        }
    }

    // MARK: - Preview

    static let preview: CatalogEntitlementService = {
        let svc = CatalogEntitlementService()
        svc.tier = .creatorPro
        svc.isLoaded = true
        return svc
    }()
}
