import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - App Store Product IDs

enum AmenProductID {
    // Individual tiers (App Store IAP via RevenueCat)
    static let bereanMonthly      = "amenapp.berean.monthly"
    static let bereanAnnual       = "amenapp.berean.annual"       // $49.99/yr
    static let creatorMonthly     = "amenapp.creator.monthly"
    static let creatorAnnual      = "amenapp.creator.annual"      // $119.99/yr
    static let ministryProMonthly = "amenapp.ministry.monthly"
    static let ministryProAnnual  = "amenapp.ministry.annual"     // $239.99/yr

    // Legacy Studio products (kept for backwards compat)
    static let studioCreatorMonthly = "amenapp.studio.creator.monthly"
    static let studioProMonthly     = "amenapp.studio.pro.monthly"
    static let studioTeamMonthly    = "amenapp.studio.team.monthly"
    static let studioCreatorAnnual  = "amenapp.studio.creator.annual"
    static let studioProAnnual      = "amenapp.studio.pro.annual"
}

// MARK: - RevenueCat Entitlement IDs

enum AmenEntitlementID {
    static let bereanPro   = "berean_pro"
    static let creatorPro  = "creator_pro"
    static let ministryPro = "ministry_pro"

    // Legacy Studio entitlements
    static let studioCreator = "studio_creator"
    static let studioPro     = "studio_pro"
    static let studioTeam    = "studio_team"
}

// MARK: - Subscription Tier

enum AmenSubscriptionTier: Int, Comparable {
    case free        = 0  // $0 — daily verse, feed, 3 Berean actions/day
    case berean      = 1  // $4.99/mo — full Bible AI, deep study, TTS, translation
    case creator     = 2  // $12.99/mo — all Berean + Studio + Tone Checker + Creator Kit
    case ministryPro = 3  // $24.99/mo — all Creator + Church Notes + Collab + Vault
    case orgMember   = 4  // Church/org plan billed via Stripe — set in Firebase, not IAP

    static func < (lhs: AmenSubscriptionTier, rhs: AmenSubscriptionTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .free:        return "Free"
        case .berean:      return "Berean"
        case .creator:     return "Creator"
        case .ministryPro: return "Ministry Pro"
        case .orgMember:   return "Organization"
        }
    }
}

// MARK: - AmenSubscriptionService

/// Single source of truth for subscription tier and feature entitlements.
///
/// Reads from Firestore `users/{uid}/entitlements/active`, which is written by:
/// - A RevenueCat webhook for App Store IAP purchases
/// - A Stripe webhook for org/church plan billing (no Apple cut)
///
/// Call `startListening()` after sign-in and `stopListening()` after sign-out.
@MainActor
final class AmenSubscriptionService: ObservableObject {
    static let shared = AmenSubscriptionService()

    @Published private(set) var tier: AmenSubscriptionTier = .free
    @Published private(set) var isOrgMember: Bool = false
    /// Specific features unlocked by org plan (e.g. "church_notes", "clip_suggestions")
    @Published private(set) var orgPlanFeatures: Set<String> = []

    private let db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?

    private init() {}

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listenerRegistration?.remove()
        let ref = db.collection("users").document(uid)
            .collection("entitlements").document("active")
        listenerRegistration = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error = error {
                dlog("⚠️ AmenSubscriptionService: \(error)")
                return
            }
            let data = snapshot?.data() ?? [:]
            let active = data["active"] as? [String] ?? []
            Task { @MainActor in
                self.tier = Self.resolveTier(from: active)
                self.isOrgMember = active.contains("org_member")
                self.orgPlanFeatures = Set(data["orgPlanFeatures"] as? [String] ?? [])
            }
        }
    }

    func stopListening() {
        listenerRegistration?.remove()
        listenerRegistration = nil
    }

    func hasEntitlement(_ id: String) -> Bool {
        switch id {
        case AmenEntitlementID.bereanPro:   return tier >= .berean
        case AmenEntitlementID.creatorPro:  return tier >= .creator
        case AmenEntitlementID.ministryPro: return tier >= .ministryPro
        case "org_member":                  return isOrgMember
        case "church_notes":                return tier >= .ministryPro || orgPlanFeatures.contains("church_notes")
        case "clip_suggestions":            return tier >= .ministryPro || orgPlanFeatures.contains("clip_suggestions")
        default:                            return false
        }
    }

    // Maps raw entitlement strings (RevenueCat or Stripe webhook) to the highest applicable tier.
    private static func resolveTier(from active: [String]) -> AmenSubscriptionTier {
        if active.contains("org_member")                          { return .orgMember }
        if active.contains(AmenEntitlementID.ministryPro) ||
           active.contains(AmenEntitlementID.studioTeam)         { return .ministryPro }
        if active.contains(AmenEntitlementID.creatorPro)  ||
           active.contains(AmenEntitlementID.studioCreator) ||
           active.contains(AmenEntitlementID.studioPro)          { return .creator }
        if active.contains(AmenEntitlementID.bereanPro)          { return .berean }
        return .free
    }
}
