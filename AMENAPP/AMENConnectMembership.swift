// AMENConnectMembership.swift
// AMENAPP
//
// Membership models, Firestore persistence, and subscription tiers for AMEN Connect.
// Free tier: browse listings, submit prayer requests, join conversations.
// Pro tier: AI matching, direct message connections, priority visibility, marketplace listings.

import SwiftUI
import Combine
import StoreKit
import FirebaseAuth
import FirebaseFirestore

// MARK: - Membership Tier

enum AMENConnectTier: String, Codable, CaseIterable {
    case free    = "Free"
    case pro     = "Pro"

    var displayName: String { rawValue }

    var monthlyPrice: String {
        switch self {
        case .free: return "Free"
        case .pro:  return "$4.99/mo"
        }
    }

    var annualPrice: String {
        switch self {
        case .free: return "Free"
        case .pro:  return "$39.99/yr"
        }
    }

    var features: [MembershipFeature] {
        switch self {
        case .free:
            return [
                MembershipFeature(icon: "magnifyingglass", text: "Browse all listings", included: true),
                MembershipFeature(icon: "hands.sparkles.fill", text: "Submit prayer requests", included: true),
                MembershipFeature(icon: "quote.bubble.fill", text: "Join conversations", included: true),
                MembershipFeature(icon: "person.3.fill", text: "Explore ministries & events", included: true),
                MembershipFeature(icon: "sparkles", text: "AI matching & suggestions", included: false),
                MembershipFeature(icon: "message.fill", text: "Direct connect requests", included: false),
                MembershipFeature(icon: "star.fill", text: "Priority profile visibility", included: false),
                MembershipFeature(icon: "storefront.fill", text: "Post marketplace listings", included: false),
            ]
        case .pro:
            return [
                MembershipFeature(icon: "magnifyingglass", text: "Browse all listings", included: true),
                MembershipFeature(icon: "hands.sparkles.fill", text: "Submit prayer requests", included: true),
                MembershipFeature(icon: "quote.bubble.fill", text: "Join conversations", included: true),
                MembershipFeature(icon: "person.3.fill", text: "Explore ministries & events", included: true),
                MembershipFeature(icon: "sparkles", text: "AI matching & suggestions", included: true),
                MembershipFeature(icon: "message.fill", text: "Direct connect requests", included: true),
                MembershipFeature(icon: "star.fill", text: "Priority profile visibility", included: true),
                MembershipFeature(icon: "storefront.fill", text: "Post marketplace listings", included: true),
            ]
        }
    }
}

struct MembershipFeature: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let included: Bool
}

// MARK: - Connect Profile

struct AMENConnectMemberProfile: Codable {
    var uid: String = ""
    var displayName: String = ""
    var bio: String = ""
    var photoURL: String = ""

    // Professional fields
    var role: String = ""               // e.g. "Worship Leader", "Software Engineer"
    var ministry: String = ""           // e.g. "Grace Community Church"
    var skills: [String] = []
    var interests: [String] = []        // matched against post keywords

    // Membership
    var tier: AMENConnectTier = .free
    var memberSince: Date = Date()
    var isVerified: Bool = false        // church/ministry badge

    // Intent signals (populated by AI keyword engine from posts)
    var intentKeywords: [String] = []   // e.g. ["looking for job", "need mentor"]
    var lastIntentUpdate: Date = Date()

    // Connection state
    var connectionCount: Int = 0
    var pendingConnectionCount: Int = 0

    // Marketplace
    var hasActiveListing: Bool = false

    // Categories they care about
    var focusCategories: [AMENConnectTab] = []
}

// MARK: - Connection Request

struct ConnectRequest: Identifiable, Codable {
    var id: String = UUID().uuidString
    var fromUID: String = ""
    var toUID: String = ""
    var fromName: String = ""
    var fromRole: String = ""
    var message: String = ""
    var status: ConnectRequestStatus = .pending
    var category: String = ""           // e.g. "Mentorship", "Jobs"
    var createdAt: Date = Date()
}

enum ConnectRequestStatus: String, Codable {
    case pending  = "pending"
    case accepted = "accepted"
    case declined = "declined"
}

// MARK: - Marketplace Listing (user-posted)

struct UserMarketplaceListing: Identifiable, Codable {
    var id: String = UUID().uuidString
    var uid: String = ""
    var authorName: String = ""
    var title: String = ""
    var description: String = ""
    var category: String = ""
    var contactEmail: String = ""
    var price: String = ""             // "Free", "$50/hr", etc.
    var tags: [String] = []
    var isActive: Bool = true
    var createdAt: Date = Date()
    var viewCount: Int = 0
}

// MARK: - AI Intent Signal

struct IntentSignal: Identifiable, Codable {
    var id: String = UUID().uuidString
    var uid: String = ""
    var keyword: String = ""           // Raw keyword extracted from post/comment
    var resolvedCategory: AMENConnectTab = .all
    var resolvedListingTitle: String = "" // Best matched listing title
    var confidence: Double = 0.0
    var sourcePostID: String = ""
    var detectedAt: Date = Date()
}

// MARK: - Membership Store (ObservableObject)

@MainActor
final class AMENConnectMembershipStore: ObservableObject {
    static let shared = AMENConnectMembershipStore()

    @Published var profile: AMENConnectMemberProfile = AMENConnectMemberProfile()
    @Published var isLoaded: Bool = false
    @Published var pendingRequests: [ConnectRequest] = []
    @Published var myListings: [UserMarketplaceListing] = []
    @Published var aiMatches: [AIConnectMatch] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: Load profile

    func loadProfile() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener?.remove()
        listener = db.collection("amenConnectProfiles").document(uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                if let data = snap?.data(),
                   let decoded = try? Firestore.Decoder().decode(AMENConnectMemberProfile.self, from: data) {
                    self.profile = decoded
                } else {
                    // Bootstrap new profile from Firebase Auth
                    var p = AMENConnectMemberProfile()
                    p.uid = uid
                    p.displayName = Auth.auth().currentUser?.displayName ?? ""
                    p.photoURL = Auth.auth().currentUser?.photoURL?.absoluteString ?? ""
                    self.profile = p
                }
                self.isLoaded = true
            }
    }

    // MARK: Save / upsert profile

    func saveProfile() async {
        guard !profile.uid.isEmpty else { return }
        let encoded = try? Firestore.Encoder().encode(profile)
        guard let data = encoded else { return }
        try? await db.collection("amenConnectProfiles").document(profile.uid).setData(data, merge: true)
    }

    // MARK: Upgrade to Pro — returns true on successful purchase

    /// Presents the StoreKit purchase sheet for the Pro monthly product.
    /// On success, syncs the tier to Firestore and returns true.
    /// On cancellation or failure, leaves the profile unchanged and returns false.
    @discardableResult
    func upgradeToPro() async -> Bool {
        let premium = PremiumManager.shared

        // Load products if not yet loaded
        if premium.products.isEmpty {
            await premium.loadProducts()
        }

        // Prefer yearly, fall back to monthly, fall back to any product
        guard let product = premium.getYearlyProduct()
                         ?? premium.getMonthlyProduct()
                         ?? premium.products.first else {
            return false
        }

        let success = await premium.purchase(product)
        if success {
            profile.tier = .pro
            await saveProfile()
        }
        return success
    }

    func downgradeFree() async {
        profile.tier = .free
        await saveProfile()
    }

    // MARK: Submit connect request

    func sendConnectRequest(toUID: String, toName: String, category: String, message: String) async throws {
        guard isPro else { throw MembershipError.proRequired }
        let uid = profile.uid
        var req = ConnectRequest()
        req.fromUID = uid
        req.toUID = toUID
        req.fromName = profile.displayName
        req.fromRole = profile.role
        req.message = message
        req.category = category
        let encoded = try Firestore.Encoder().encode(req)
        try await db.collection("connectRequests").document(req.id).setData(encoded)
    }

    // MARK: Post marketplace listing

    func postListing(_ listing: UserMarketplaceListing) async throws {
        guard isPro else { throw MembershipError.proRequired }
        let encoded = try Firestore.Encoder().encode(listing)
        try await db.collection("amenConnectMarketplace").document(listing.id).setData(encoded)
        profile.hasActiveListing = true
        await saveProfile()
    }

    // MARK: Update intent keywords (called by AI match engine)

    func updateIntentKeywords(_ keywords: [String]) async {
        profile.intentKeywords = keywords
        profile.lastIntentUpdate = Date()
        await saveProfile()
    }

    // MARK: Cleanup

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    /// Pro if either the Connect profile tier is .pro OR the central PremiumManager
    /// shows an active subscription (single source of truth for StoreKit status).
    var isPro: Bool {
        profile.tier == .pro || PremiumManager.shared.hasProAccess
    }
}

// MARK: - Membership Error

enum MembershipError: LocalizedError {
    case proRequired
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .proRequired: return "Upgrade to AMEN Connect Pro to use this feature."
        case .notSignedIn: return "Please sign in to continue."
        }
    }
}

// MARK: - AI Connect Match (result from engine)

struct AIConnectMatch: Identifiable {
    let id = UUID()
    let keyword: String             // Trigger keyword from user's post
    let matchedTab: AMENConnectTab
    let matchedListingTitle: String
    let matchedListingOrg: String
    let matchedListingIcon: String
    let matchedListingColor: Color
    let confidence: Double          // 0–1
    let suggestion: String          // Human-readable "We noticed you..." text
}
