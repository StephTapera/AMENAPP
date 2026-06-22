// AmenObjectRepository.swift
// AMEN App — CommunityOS / Core
//
// Phase 1 — Agent A1 (Core Platform Architecture)
// Firestore-direct repository for reading and writing core AmenObjects.
//
// DISTINCT FROM:
//   FirebaseTransformEngine (TransformEngine.swift) — CF-backed transform actor.
//   EdgeService (EdgeService.swift)                 — CF-backed edge service.
//
// Rules:
//   - async/await only — no Combine.
//   - @MainActor on the ObservableObject class.
//   - Soft-delete only: never calls .delete(); sets { isDeleted: true }.
//   - All writes use FieldValue.serverTimestamp() for timestamps.
//   - No force-unwraps; guard let or throws everywhere.
//
// SHARED TYPES USED (do NOT redefine):
//   AmenObjectType, SpawnProvenance, AmenIntent  →  CommunityObjectTypes.swift
//   TransformError                               →  TransformEngine.swift
//   AmenPost, AmenPrayer, etc.                  →  AmenCoreModels.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - RepositoryError

/// Errors thrown by AmenObjectRepository not covered by TransformError.
enum RepositoryError: Error {
    /// Firestore document not found in the given collection.
    case documentNotFound(collection: String, id: String)
    /// Firebase Auth user is nil or UID is empty.
    case unauthenticated
    /// Firestore document failed to decode to the expected type.
    case decodingFailed(collection: String, id: String)
}

// MARK: - AmenObjectRepository

@MainActor
final class AmenObjectRepository: ObservableObject {

    // MARK: - Private

    private let db = Firestore.firestore()
    private let engine = AmenTransformEngine()

    // MARK: - Collection Name Constants

    private enum Collection {
        static let posts                  = "posts"
        static let prayers                = "prayers"
        static let discussions            = "objectDiscussionRooms"
        static let studies                = "studies"
        static let events                 = "events"
        static let volunteerOpportunities = "volunteerOpportunities"
        static let mentorships            = "mentorships"
        static let jobs                   = "jobs"
        static let mediaObjects           = "mediaObjects"
        // User-owned sub-collections accessed via userSubCollection(uid:name:)
    }

    // MARK: - Fetch: AmenPost

    /// Fetches a single AmenPost by document ID from /posts/{id}.
    func fetchPost(id: String) async throws -> AmenPost {
        try await fetch(collection: Collection.posts, id: id)
    }

    // MARK: - Fetch: AmenPrayer

    /// Fetches a single AmenPrayer by document ID from /prayers/{id}.
    func fetchPrayer(id: String) async throws -> AmenPrayer {
        try await fetch(collection: Collection.prayers, id: id)
    }

    // MARK: - Fetch: AmenDiscussion

    /// Fetches an AmenDiscussion from the nested path:
    /// /objectDiscussionRooms/{parentId}/rooms/{roomId}.
    ///
    /// OPEN (OQ-4): parentId should be namespaced as "{objectType}_{canonicalObjectId}"
    ///              to prevent ID collision; confirm before all agents adopt this path.
    func fetchDiscussion(id: String) async throws -> AmenDiscussion {
        try await fetch(collection: Collection.discussions, id: id)
    }

    /// Fetches a discussion from the nested /objectDiscussionRooms/{parentId}/rooms/{roomId} path.
    func fetchDiscussionInRoom(_ roomId: String, parentId: String) async throws -> AmenDiscussion {
        let docRef = db
            .collection(Collection.discussions)
            .document(parentId)
            .collection("rooms")
            .document(roomId)
        let snap = try await docRef.getDocument()
        guard snap.exists else {
            throw RepositoryError.documentNotFound(
                collection: "objectDiscussionRooms/\(parentId)/rooms",
                id: roomId
            )
        }
        do {
            return try snap.data(as: AmenDiscussion.self)
        } catch {
            throw RepositoryError.decodingFailed(
                collection: "objectDiscussionRooms/\(parentId)/rooms",
                id: roomId
            )
        }
    }

    // MARK: - Fetch: AmenJob

    /// Fetches a single AmenJob by document ID from /jobs/{id}.
    func fetchJob(id: String) async throws -> AmenJob {
        try await fetch(collection: Collection.jobs, id: id)
    }

    // MARK: - Generic Fetch Helper

    /// Fetches any AmenObject-conforming Codable from a top-level collection by document ID.
    /// Throws `RepositoryError.documentNotFound` if the document does not exist.
    private func fetch<T: AmenObject & Decodable>(
        collection: String,
        id: String
    ) async throws -> T {
        let docRef = db.collection(collection).document(id)
        let snap = try await docRef.getDocument()
        guard snap.exists else {
            throw RepositoryError.documentNotFound(collection: collection, id: id)
        }
        do {
            return try snap.data(as: T.self)
        } catch {
            throw RepositoryError.decodingFailed(collection: collection, id: id)
        }
    }

    // MARK: - createSpawnedObject

    /// Runs the transform engine, writes a new derived object to Firestore,
    /// and returns the new document ID.
    ///
    /// Provenance is included in the write; `createdAt` and `updatedAt` use
    /// `FieldValue.serverTimestamp()`.
    ///
    /// C1 §3c: if the source was itself spawned (hop > 1), sourceRef is set to
    /// the hop-1 ancestor — not the intermediate — preserving the canonical chain.
    ///
    /// - Parameters:
    ///   - source: The originating spawnable object.
    ///   - sourceObjectType: Explicit AmenObjectType for the source (avoids inference).
    ///   - intent: The C2 AmenIntent driving this transform.
    ///   - actorId: Firebase Auth UID of the user initiating the transform.
    ///   - targetCollection: Firestore collection name for the new object.
    ///   - additionalFields: Extra Firestore fields to merge into the document payload.
    ///   - additionalProvenanceFields: Extra fields to merge into the provenance sub-doc.
    /// - Returns: The Firestore document ID of the newly created object.
    /// - Throws: `TransformError` on unsupported combinations or missing provenance.
    func createSpawnedObject<S: SpawnableObject>(
        from source: S,
        sourceObjectType: AmenObjectType,
        intent: AmenIntent,
        actorId: String,
        targetCollection: String,
        additionalFields: [String: Any] = [:],
        additionalProvenanceFields: [String: Any] = [:]
    ) async throws -> String {
        // Verify the actor is authenticated.
        guard let currentUser = Auth.auth().currentUser, !currentUser.uid.isEmpty else {
            throw TransformError.actorNotAuthorized(requiredRole: .visitor)
        }

        // Determine the canonical sourceRef (hop-1 per C1 §3c).
        let sourceRef: String
        if let hop1Ref = source.provenance?.sourceRef {
            // Source was itself spawned — point to its ancestor, not the source.
            sourceRef = hop1Ref
        } else {
            sourceRef = "/\(targetCollection)/\(source.id)"
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
            "sourceType":  provenance.sourceType,
            "intent":      provenance.intent,
            "createdAt":   FieldValue.serverTimestamp()
        ]
        if let ref = provenance.sourceRef {
            provenanceData["sourceRef"] = ref
        }
        if let ownerId = provenance.sourceOwnerId {
            provenanceData["sourceOwnerId"] = ownerId
        }
        for (k, v) in additionalProvenanceFields {
            provenanceData[k] = v
        }

        // Write the new derived object document.
        let newDocRef = db.collection(targetCollection).document()
        var payload: [String: Any] = [
            "id":         newDocRef.documentID,
            "_type":      targetCollection,
            "createdBy":  actorId,
            "createdAt":  FieldValue.serverTimestamp(),
            "updatedAt":  FieldValue.serverTimestamp(),
            "isDeleted":  false,
            "provenance": provenanceData
        ]
        for (k, v) in additionalFields {
            payload[k] = v
        }

        try await newDocRef.setData(payload)
        return newDocRef.documentID
    }

    // MARK: - softDelete

    /// Soft-deletes a document: sets `{ isDeleted: true, updatedAt: serverTimestamp }`.
    /// Never calls `.delete()`. Safe to call on already-deleted documents.
    func softDelete(collection: String, id: String) async throws {
        try await db.collection(collection).document(id).updateData([
            "isDeleted": true,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - softDeleteRoom (nested)

    /// Soft-deletes a nested discussion room document.
    func softDeleteRoom(parentId: String, roomId: String) async throws {
        try await db
            .collection(Collection.discussions)
            .document(parentId)
            .collection("rooms")
            .document(roomId)
            .updateData([
                "isDeleted": true,
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }

    // MARK: - Private helpers

    /// Returns a Firestore reference for a user-owned sub-collection.
    private func userSubCollection(uid: String, name: String) -> CollectionReference {
        db.collection("users").document(uid).collection(name)
    }
}
