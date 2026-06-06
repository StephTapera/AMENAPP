// EntitlementService.swift — AMEN EntitlementOS
// Checks and vends user entitlements. Single source of truth for feature access.
import Foundation
import FirebaseAuth
import FirebaseFirestore

enum AmenEntitlementTier: String, Codable {
    case free, amenPlus = "amen_plus", amenPro = "amen_pro", creatorPro = "creator_pro", churchPro = "church_pro"
}

@MainActor
final class EntitlementService: ObservableObject {
    static let shared = EntitlementService()
    private init() {}

    @Published var tier: AmenEntitlementTier = .free
    @Published var isEmailVerified: Bool = false
    @Published var isAccountActive: Bool = true  // false = suspended/deleted

    private var db: Firestore { Firestore.firestore() }

    func refresh() async {
        guard let user = Auth.auth().currentUser else {
            isAccountActive = false; return
        }
        isEmailVerified = user.isEmailVerified
        do {
            let doc = try await db.collection("users").document(user.uid).getDocument()
            let data = doc.data() ?? [:]
            let rawTier = data["subscriptionTier"] as? String ?? "free"
            tier = AmenEntitlementTier(rawValue: rawTier) ?? .free
            // If soft-deleted, mark inactive
            if data["deletedAt"] != nil { isAccountActive = false }
        } catch {
            dlog("[EntitlementService] refresh failed: \(error)")
        }
    }

    func requiresPlus() -> Bool { tier == .free }
    func hasPro() -> Bool { tier == .amenPro || tier == .creatorPro || tier == .churchPro }
}
