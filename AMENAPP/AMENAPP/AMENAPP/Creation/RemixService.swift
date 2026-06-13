// RemixService.swift
// AMEN App — Remix lineage creation and chain retrieval
//
// Creates RemixLineage records in Firestore at remixLineage/{id}.
// Transactionally resolves rootArtifactId: if the parent artifact already
// has a lineage record, the grandparent's rootArtifactId is inherited so
// the entire chain traces back to a single root.
//
// Flag-gated: AMENFeatureFlags.shared.remixLineage

import Foundation
import FirebaseAuth
import FirebaseFunctions
import FirebaseFirestore

@MainActor
final class RemixService: ObservableObject {

    // MARK: - Dependencies

    private let functions = Functions.functions(region: "us-central1")
    private let db = Firestore.firestore()

    // MARK: - Create Remix

    /// Creates a remix: writes RemixLineage to Firestore at remixLineage/{id}.
    ///
    /// Transaction logic:
    ///   - Reads parent artifact's existing lineage (if any) to extract rootArtifactId.
    ///   - If no prior lineage exists for the parent, parentArtifactId IS the root.
    ///   - Writes the new RemixLineage doc atomically.
    ///
    /// Delegates to the createRemixLineage Cloud Function for transactional safety.
    func createRemix(
        parentArtifactId: String,
        childArtifactId: String,
        creatorUid: String
    ) async throws -> RemixLineage {
        guard AMENFeatureFlags.shared.remixLineage else {
            throw RemixServiceError.flagDisabled
        }

        let data: [String: Any] = [
            "parentArtifactId": parentArtifactId,
            "childArtifactId": childArtifactId,
            "creatorUid": creatorUid
        ]

        let result = try await functions.httpsCallable("createRemixLineage").call(data)

        guard
            let dict = result.data as? [String: Any],
            let id = dict["id"] as? String,
            let rootId = dict["rootArtifactId"] as? String,
            let parentId = dict["parentArtifactId"] as? String,
            let childId = dict["childArtifactId"] as? String,
            let uid = dict["creatorUid"] as? String,
            let ts = dict["createdAt"] as? Double
        else {
            throw RemixServiceError.unexpectedResponse
        }

        return RemixLineage(
            id: id,
            rootArtifactId: rootId,
            parentArtifactId: parentId,
            childArtifactId: childId,
            creatorUid: uid,
            createdAt: Date(timeIntervalSince1970: ts / 1000)
        )
    }

    // MARK: - Lineage Chain

    /// Fetches the full lineage chain for an artifact (root → ... → artifact).
    /// Returns lineage records ordered from root to the given artifact.
    func lineageChain(for artifactId: String) async throws -> [RemixLineage] {
        guard AMENFeatureFlags.shared.remixLineage else {
            throw RemixServiceError.flagDisabled
        }

        // Fetch the lineage entry for this artifact (where childArtifactId == artifactId)
        let snapshot = try await db.collection("remixLineage")
            .whereField("childArtifactId", isEqualTo: artifactId)
            .limit(to: 1)
            .getDocuments()

        guard let doc = snapshot.documents.first else {
            // No lineage — this is a root artifact
            return []
        }

        guard let rootId = doc.data()["rootArtifactId"] as? String else {
            return []
        }

        // Fetch all lineage entries sharing the same root
        let chainSnapshot = try await db.collection("remixLineage")
            .whereField("rootArtifactId", isEqualTo: rootId)
            .order(by: "createdAt")
            .getDocuments()

        return chainSnapshot.documents.compactMap { d -> RemixLineage? in
            let data = d.data()
            guard
                let id = data["id"] as? String,
                let root = data["rootArtifactId"] as? String,
                let parent = data["parentArtifactId"] as? String,
                let child = data["childArtifactId"] as? String,
                let creator = data["creatorUid"] as? String,
                let ts = data["createdAt"] as? Timestamp
            else { return nil }

            return RemixLineage(
                id: id,
                rootArtifactId: root,
                parentArtifactId: parent,
                childArtifactId: child,
                creatorUid: creator,
                createdAt: ts.dateValue()
            )
        }
    }
}

// MARK: - Error

enum RemixServiceError: LocalizedError {
    case flagDisabled
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .flagDisabled:
            return "Remix lineage is not available right now."
        case .unexpectedResponse:
            return "Unexpected response from the lineage service."
        }
    }
}
