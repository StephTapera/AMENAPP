// AmenObjectRepository.swift
// AMEN App — CommunityOS / Core
//
// Phase 1 — Agent A1 (Core Platform Architecture)
// Firestore-backed repository for reading and writing core AmenObjects.
//
// Rules:
//   - async/await only — no Combine.
//   - @MainActor on the ObservableObject class.
//   - Soft-delete only: never calls .delete(); sets { isDeleted: true }.
//   - All writes use FieldValue.serverTimestamp() for timestamps.
//   - No force-unwraps; guard let or throws everywhere.

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - AmenObjectRepository

@MainActor
final class AmenObjectRepository: ObservableObject {

    // MARK: - Private

    private let db = Firestore.firestore()
    private let engine = AmenTransformEngine()

    // MARK: - Collection Name Constants

    private enum Collection {
        static let posts                    = "posts"
        static let prayers                  = "prayers"
        static let discussions              = "objectDiscussionRooms"
        static let studies                  = "studies"
        static let events                   = "events"
        static let volunteerOpportunities   = "volunteerOpportunities"
        static let mentorships              = "mentorships"
        static let jobs                     = "jobs"
        static let mediaObjects             = "mediaObjects"
        // User-owned sub-collections: /users/{uid}/churchNotes, /users/{uid}/bereanInsights
    }

    // MARK: - Fetch: AmenPost

    /// Fetches a single AmenPost by document ID from /posts/{id}.
    /// - Throws: Firestore decode error or a generic error if the document doesn't exist.
    func fetchPost(id: String) async throws -> AmenPost {
        try await fetch(collection: Collection.posts, id: id)
    }

    // MARK: - Fetch: AmenPrayer

    /// Fetches a single AmenPrayer by document ID from /prayers/{id}.
    func fetchPrayer(id: String) async throws -> AmenPrayer {
        try await fetch(collection: Collection.prayers, id: id)
    }

    // MARK: - Fetch: AmenDiscussion

    /// Fetches an AmenDiscussion from the root rooms collection.
    ///
    /// NOTE: The canonical path is /objectDiscussionRooms/{canonicalObjectId}/rooms/{roomId}.
    /// This helper fetches from the top-level alias. Use `fetchDiscussionInRoom(_:parentId:)`
    /// for the nested path.
    func fetchDiscussion(id: String) async throws -> AmenDiscussion {
        try await fetch(collection: Collection.discussions, id: id)
    }

    /// Fetches an AmenDiscussion from the nested /objectDiscussionRooms/{parentId}/rooms/{roomId}.
    /// OPEN (OQ-4): parentId should be namespaced as "{objectType}_{canonicalObjectId}"
    ///              to avoid ID collision; confirm before all feature agents adopt this path.
    func fetchDiscussionInRoom(_ roomId: String, parentId: String) async throws -> AmenDiscussion {
        let docRef = db
            .collection(Collection.discussions)
            .document(parentId)
            .collection("rooms")
            .document(roomId)
        let snap = try await docRef.getDocument()
        guard snap.exists else {
            throw RepositoryError.documentNotFound(collection: "objectDiscussionRooms/\(parentId)/rooms", id: roomId)
        }
        return try snap.data(as: AmenDiscussion.self)
    }

    // MARK: - Fetch: AmenJob

    /// Fetches a single AmenJob by document ID from /jobs/{id}.
    func fetchJob(id: String) async throws -> AmenJob {
        try await fetch(collection: Collection.jobs, id: id)
    }

    // MARK: - Generic Fetch Helper

    /// Fetches any AmenObject-conforming Codable type from a top-level collection by ID.
    /// - Throws: `RepositoryError.documentNotFound` if the document does not exist.
    private func fetch<T: AmenObject & Decodable>(
        collection: String,
        id: String
    ) async throws -> T {
        let docRef = db.collection(collection).document(id)
        let snap = try await docRef.getDocument()
        guard snap.exists else {
            throw RepositoryError.documentNotFound(collection: collection, id: id)
        }
        return try snap.data(as: T.self)
    }

    // MARK: - createSpawnedObject

    /// Runs the transform engine, writes a new derived object to Firestore,
    /// and returns the new document ID.
    ///
    /// The provenance block is included in the write. `createdAt` and `updatedAt`
    /// are always set via `FieldValue.serverTimestamp()`.
    ///
    /// - Parameters:
    ///   - source: The originating spawnable object.
    ///   - intent: The C2 intent driving this transform.
    ///   - actorId: Firebase Auth UID of the user initiating the transform.
    ///   - collection: Firestore collection name for the new object.
    ///   - provenanceFields: Additional Firestore-safe fields to merge into the
    ///                       provenance sub-document (e.g., eventDate, orgId).
    /// - Returns: The Firestore document ID of the newly created object.
    /// - Throws: `TransformError` on unsupported combinations or missing provenance.
    ///           Firestore errors on write failures.
    func createSpawnedObject<S: SpawnableObject>(
        from source: S,
        intent: Intent,
        actorId: String,
        collection: String,
        additionalProvenanceFields: [String: Any] = [:]
    ) async throws -> String {
        guard let currentUser = Auth.auth().currentUser, !currentUser.uid.isEmpty else {
            throw TransformError.actorNotAuthorized(requiredRole: "authenticated")
        }

        // Resolve the ObjectType from the source's provenance chain or default.
        // SpawnableObject does not directly carry objectType; infer from the source's
        // existing provenance or use the collection name as a fallback.
        // OPEN: Once all AmenObject types carry a typed objectType property, replace
        //       this inference with a protocol requirement.
        let sourceTypeRaw: String
        if let existingProvenance = source.provenance {
            // If the source was itself spawned, record the hop-1 ancestor as the source.
            // C1 §3c: sourceRef = original (hop 1), not the intermediate.
            sourceTypeRaw = existingProvenance.sourceType
        } else {
            // Root object — use collection name as a type hint. Caller should pass
            // an accurate collection that maps to an ObjectType raw value.
            sourceTypeRaw = String(collection.dropLast(collection.hasSuffix("s") ? 1 : 0))
        }

        guard let sourceObjectType = ObjectType(rawValue: sourceTypeRaw) else {
            throw TransformError.missingRequiredProvenance(field: "sourceObjectType")
        }

        // Determine the Firestore document path for provenance.sourceRef.
        // Use hop-1 sourceRef if source was itself spawned (preserves the original).
        let sourceRef: String
        if let hop1Ref = source.provenance?.sourceRef {
            sourceRef = hop1Ref
        } else {
            sourceRef = "/\(collection)/\(source.id)"
        }

        let (_, provenance) = try engine.transform(
            sourceType: sourceObjectType,
            sourceRef: sourceRef,
            sourceOwnerId: source.createdBy,
            intent: intent,
            actorId: actorId,
            audience: nil
        )

        // Build the Firestore provenance sub-document.
        var provenanceData: [String: Any] = [
            "sourceType":    provenance.sourceType,
            "intent":        provenance.intent,
            "createdAt":     FieldValue.serverTimestamp()
        ]
        if let ref = provenance.sourceRef {
            provenanceData["sourceRef"] = ref
        }
        if let ownerId = provenance.sourceOwnerId {
            provenanceData["sourceOwnerId"] = ownerId
        }
        // Merge any caller-supplied additional fields (eventDate, orgId, etc.).
        for (k, v) in additionalProvenanceFields {
            provenanceData[k] = v
        }

        // Write the new derived object document.
        let newDocRef = db.collection(collection).document()
        let payload: [String: Any] = [
            "id":               newDocRef.documentID,
            "_type":            collection,   // OPEN: use proper ObjectType raw value
            "createdBy":        actorId,
            "createdAt":        FieldValue.serverTimestamp(),
            "updatedAt":        FieldValue.serverTimestamp(),
            "isDeleted":        false,
            "provenance":       provenanceData
        ]
        try await newDocRef.setData(payload)
        return newDocRef.documentID
    }

    // MARK: - softDelete

    /// Marks a document as deleted by setting `{ isDeleted: true, updatedAt: serverTimestamp }`.
    /// Never calls `.delete()`. Safe to call on already-deleted documents.
    ///
    /// - Parameters:
    ///   - collection: Top-level Firestore collection name.
    ///   - id: Document ID.
    func softDelete(collection: String, id: String) async throws {
        let docRef = db.collection(collection).document(id)
        try await docRef.updateData([
            "isDeleted": true,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - softDelete (nested room)

    /// Soft-deletes a nested room document, e.g., inside objectDiscussionRooms.
    func softDeleteRoom(parentId: String, roomId: String) async throws {
        let docRef = db
            .collection(Collection.discussions)
            .document(parentId)
            .collection("rooms")
            .document(roomId)
        try await docRef.updateData([
            "isDeleted": true,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }
}

// MARK: - RepositoryError

/// Errors thrown by AmenObjectRepository that are not covered by TransformError.
enum RepositoryError: Error {
    /// The Firestore document was not found in the given collection.
    case documentNotFound(collection: String, id: String)
    /// The current Firebase Auth user is nil or their UID is empty.
    case unauthenticated
    /// A required field was missing from the Firestore document on decode.
    case decodingFailed(field: String)
}
