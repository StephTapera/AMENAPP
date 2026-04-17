import Foundation
import FirebaseAuth
import FirebaseFirestore

struct CreatorSafetyDecision: Codable, Hashable {
    var isAllowed: Bool
    var reason: String?
}

protocol CreatorSafetyServicing {
    func evaluateAsset(_ asset: CreatorAsset) async throws -> CreatorSafetyDecision
    func evaluateProject(_ project: CreatorProject) async throws -> CreatorSafetyDecision
}

final class CreatorSafetyService: CreatorSafetyServicing {
    private lazy var db = Firestore.firestore()

    func evaluateAsset(_ asset: CreatorAsset) async throws -> CreatorSafetyDecision {
        _ = try requireOwnerID()
        // TODO: integrate moderation service or policy docs.
        return CreatorSafetyDecision(isAllowed: true, reason: nil)
    }

    func evaluateProject(_ project: CreatorProject) async throws -> CreatorSafetyDecision {
        _ = try requireOwnerID()
        // TODO: integrate authenticity + moderation checks.
        return CreatorSafetyDecision(isAllowed: true, reason: nil)
    }

    private func requireOwnerID() throws -> String {
        guard let ownerID = Auth.auth().currentUser?.uid, !ownerID.isEmpty else {
            throw CreatorServiceError.notFound
        }
        return ownerID
    }
}
