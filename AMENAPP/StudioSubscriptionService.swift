//
//  StudioSubscriptionService.swift
//  AMENAPP
//
//  RevenueCat-powered subscription management for AMEN Studio.
//  Replaces direct StoreKit 2 calls with RevenueCat SDK for:
//    - Server-side receipt validation
//    - Restore purchases
//    - Entitlement analytics
//    - Paywall A/B testing support
//
//  Tiers:
//    Free     — 3 creates/month, read-only collab
//    Creator  — $7.99/mo — unlimited creates, AI Muse, export
//    Pro      — $14.99/mo — + Collab, Vault, multi-publish
//    Team     — $24.99/mo — up to 10 members, shared workspace
//
//  RevenueCat entitlement IDs (configure in RC dashboard):
//    "studio_creator", "studio_pro", "studio_team"
//
//  SDK: https://github.com/RevenueCat/purchases-ios
//  Add via Xcode → File → Add Package Dependencies
//

import Combine
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
#if canImport(RevenueCat)
import RevenueCat
#endif

// MARK: - Entitlement

enum StudioEntitlement {
    case free
    case creator    // $7.99/mo
    case pro        // $14.99/mo
    case team       // $24.99/mo

    var createsPerMonth: Int {
        switch self {
        case .free: return 3
        case .creator, .pro, .team: return .max
        }
    }

    var canUseAIMuse: Bool { self != .free }
    var canExport: Bool { self != .free }
    var canCollab: Bool { self == .pro || self == .team }
    var canUseVault: Bool { self == .pro || self == .team }
    var maxTeamMembers: Int {
        switch self {
        case .team: return 10
        default: return 1
        }
    }

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .creator: return "Creator"
        case .pro: return "Pro"
        case .team: return "Team"
        }
    }

    var priceLabel: String {
        switch self {
        case .free: return "Free"
        case .creator: return "$7.99/mo"
        case .pro: return "$14.99/mo"
        case .team: return "$24.99/mo"
        }
    }

    var accent: Color {
        switch self {
        case .free: return .secondary
        case .creator: return .blue
        case .pro: return .purple
        case .team: return Color(red: 0.9, green: 0.6, blue: 0.1)
        }
    }
}

// MARK: - Product IDs (used to match RC packages by store product ID)

private enum StudioProductID {
    static let creatorMonthly = "amenapp.studio.creator.monthly"
    static let proMonthly     = "amenapp.studio.pro.monthly"
    static let teamMonthly    = "amenapp.studio.team.monthly"
    static let creatorAnnual  = "amenapp.studio.creator.annual"
    static let proAnnual      = "amenapp.studio.pro.annual"
}

// MARK: - RevenueCat Entitlement IDs

private enum RCEntitlementID {
    static let creator = "studio_creator"
    static let pro     = "studio_pro"
    static let team    = "studio_team"
}

// MARK: - Service

@MainActor
final class StudioSubscriptionService: ObservableObject {
    static let shared = StudioSubscriptionService()

    @Published private(set) var entitlement: StudioEntitlement = .free
    @Published private(set) var isPurchasing = false
    @Published private(set) var purchaseError: String?
    @Published private(set) var freeCreatesUsed: Int = 0

    #if canImport(RevenueCat)
    @Published private(set) var offerings: Offerings?
    /// All available packages from the current RC offering.
    var packages: [Package] { offerings?.current?.availablePackages ?? [] }
    #endif

    private let db = Firestore.firestore()

    private init() {
        configureRevenueCat()
        Task { await refresh() }
    }

    // MARK: - Configuration

    private func configureRevenueCat() {
        #if canImport(RevenueCat)
        let key = Bundle.main.infoDictionary?["REVENUECAT_API_KEY"] as? String ?? ""
        guard !key.isEmpty, key != "$(REVENUECAT_API_KEY)" else {
            dlog("⚠️ REVENUECAT_API_KEY not set — purchases disabled")
            return
        }
        Purchases.configure(withAPIKey: key)
        Purchases.logLevel = .warn
        if let uid = Auth.auth().currentUser?.uid {
            Purchases.shared.logIn(uid) { _, _, _ in }
        }
        #else
        dlog("⚠️ RevenueCat not installed — purchases disabled")
        #endif
    }

    // MARK: - Entitlement Check

    func requiresUpgrade(for feature: StudioFeature) -> Bool {
        switch feature {
        case .create:
            return entitlement == .free && freeCreatesUsed >= 3
        case .aiMuse:
            return !entitlement.canUseAIMuse
        case .export:
            return !entitlement.canExport
        case .collab:
            return !entitlement.canCollab
        case .vault:
            return !entitlement.canUseVault
        }
    }

    enum StudioFeature {
        case create, aiMuse, export, collab, vault
    }

    // MARK: - Load Offerings

    #if canImport(RevenueCat)
    /// Called by paywall to populate the package list.
    func loadProducts() async { await loadOfferings() }

    func loadOfferings() async {
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            dlog("⚠️ StudioSubscription: failed to load offerings: \(error)")
        }
    }

    // MARK: - Purchase

    func purchase(_ package: Package) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            if !result.userCancelled {
                updateEntitlement(from: result.customerInfo)
            }
        } catch {
            purchaseError = error.localizedDescription
            dlog("⚠️ StudioSubscription purchase error: \(error)")
        }
    }

    // MARK: - Restore

    func restore() async {
        do {
            let info = try await Purchases.shared.restorePurchases()
            updateEntitlement(from: info)
        } catch {
            dlog("⚠️ StudioSubscription restore error: \(error)")
        }
    }
    #endif

    // MARK: - Track Free Tier Usage

    func recordCreate() {
        guard entitlement == .free else { return }
        freeCreatesUsed = min(freeCreatesUsed + 1, 100)
        UserDefaults.standard.set(freeCreatesUsed, forKey: freeCreatesKey)
    }

    private var freeCreatesKey: String {
        let month = Calendar.current.component(.month, from: Date())
        let year = Calendar.current.component(.year, from: Date())
        return "studioFreeCreates_\(year)_\(month)"
    }

    // MARK: - Private

    private func refresh() async {
        freeCreatesUsed = UserDefaults.standard.integer(forKey: freeCreatesKey)
        #if canImport(RevenueCat)
        await loadOfferings()
        do {
            let info = try await Purchases.shared.customerInfo()
            updateEntitlement(from: info)
        } catch {
            dlog("⚠️ StudioSubscription: failed to fetch customer info: \(error)")
        }
        #endif
    }

    #if canImport(RevenueCat)
    private func updateEntitlement(from customerInfo: CustomerInfo) {
        let e = customerInfo.entitlements.all
        let tier: StudioEntitlement
        if e[RCEntitlementID.team]?.isActive == true {
            tier = .team
        } else if e[RCEntitlementID.pro]?.isActive == true {
            tier = .pro
        } else if e[RCEntitlementID.creator]?.isActive == true {
            tier = .creator
        } else {
            tier = .free
        }
        entitlement = tier
        syncEntitlementToFirestore(tier)
    }
    #endif

    private func syncEntitlementToFirestore(_ tier: StudioEntitlement) {
        guard let uid = Auth.auth().currentUser?.uid, tier != .free else { return }
        Task.detached { [weak self] in
            guard let self else { return }
            try? await self.db.collection("users").document(uid).updateData([
                "studioTier": tier.displayName,
                "studioTierUpdatedAt": FieldValue.serverTimestamp()
            ])
        }
    }
}
