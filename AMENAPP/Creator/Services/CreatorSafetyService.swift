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

    private static let trustedStorageHosts = [
        "firebasestorage.googleapis.com",
        "storage.googleapis.com",
        "amenapp"
    ]

    func evaluateAsset(_ asset: CreatorAsset) async throws -> CreatorSafetyDecision {
        _ = try requireOwnerID()
        // Verify the asset URL originates from a trusted AMEN storage domain.
        if let urlString = asset.downloadURL ?? asset.storagePath,
           let host = URL(string: urlString)?.host {
            let trusted = Self.trustedStorageHosts.contains(where: { host.contains($0) })
            if !trusted {
                return CreatorSafetyDecision(
                    isAllowed: false,
                    reason: "Asset URL does not originate from a trusted AMEN storage domain."
                )
            }
        }
        return CreatorSafetyDecision(isAllowed: true, reason: nil)
    }

    func evaluateProject(_ project: CreatorProject) async throws -> CreatorSafetyDecision {
        let ownerID = try requireOwnerID()
        let decision = await ModerationPipeline.shared.evaluate(
            text: project.title,
            context: .post,
            userId: ownerID
        )
        if decision.action.isBlocking {
            return CreatorSafetyDecision(
                isAllowed: false,
                reason: "Project title contains content that violates AMEN community guidelines."
            )
        }
        return CreatorSafetyDecision(isAllowed: true, reason: nil)
    }

    private func requireOwnerID() throws -> String {
        guard let ownerID = Auth.auth().currentUser?.uid, !ownerID.isEmpty else {
            throw CreatorServiceError.notFound
        }
        return ownerID
    }
}
