import Foundation
import FirebaseAuth
import FirebaseFirestore

struct CreatorEntitlementState: Codable, Hashable {
    var isPremium: Bool
    var maxProjects: Int
    var maxVideoDurationSeconds: Int
    var canUseTranslations: Bool
}

protocol CreatorEntitlementServicing {
    func fetchEntitlements(ownerID: String) async throws -> CreatorEntitlementState
}

final class CreatorEntitlementService: CreatorEntitlementServicing {
    private lazy var db = Firestore.firestore()

    func fetchEntitlements(ownerID: String) async throws -> CreatorEntitlementState {
        let snapshot = try await db.collection("creatorEntitlements")
            .document(ownerID)
            .getDocument()

        if let data = snapshot.data(),
           let state = try? CreatorFirestoreCoder.decode(CreatorEntitlementState.self, from: data) {
            return state
        }

        return CreatorEntitlementState(isPremium: false, maxProjects: 3, maxVideoDurationSeconds: 90, canUseTranslations: false)
    }
}
