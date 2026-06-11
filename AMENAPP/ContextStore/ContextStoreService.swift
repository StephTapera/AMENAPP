//
//  ContextStoreService.swift
//  AMENAPP — Universal Migration & Context System (Wave 1)
//
//  The ONLY writable surface for ContextFacet + ContextSnapshot. Everything else
//  (Identity Blueprint, Operating Manual, Life Capsule, Context QR, .amen export)
//  is a PROJECTION over the facets this service owns.
//
//  Hard invariants enforced here (mirrored by firestore.rules + Aegis):
//   - Master gate: nothing runs unless AMENFeatureFlags.shared.contextSystemEnabled.
//   - Tier table is law: every write must satisfy facet.hasValidTier.
//   - Approval before persistence: provenance.userApproved == true AND
//     AegisEnforcementService.shared.verifySanitization(provenance) passes.
//   - Tier-P facets are NEVER sent to a Cloud Function or logged. (This service
//     writes only to the owner's own Firestore docs, which is allowed; it never
//     emits facet values to a CF, and never logs facet values.)
//   - Snapshots are append-only.
//
//  No content import: this service never reads/writes messages, posts, media, or
//  contacts. It only handles ContextFacet / ContextSnapshot documents.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Errors

/// Clear, loud failures for every guard the store enforces. Never silently drop.
enum ContextStoreError: LocalizedError, Equatable {
    case contextSystemDisabled
    case notSignedIn
    case invalidTier(expected: EncryptionTier, actual: EncryptionTier)
    case notApproved
    case sanitizationFailed
    case ownerMismatch
    case invalidSchemaVersion(Int)

    var errorDescription: String? {
        switch self {
        case .contextSystemDisabled:
            return "The Context System is turned off (contextSystemEnabled == false)."
        case .notSignedIn:
            return "No signed-in user; cannot read or write context facets."
        case .invalidTier(let expected, let actual):
            return "Facet tier \(actual.rawValue) does not match the canonical tier \(expected.rawValue) for its category/key."
        case .notApproved:
            return "Facet cannot be persisted: provenance.userApproved is false (approval before persistence, §1.7)."
        case .sanitizationFailed:
            return "Facet cannot be persisted: Aegis C59 sanitization receipt is missing or unverified."
        case .ownerMismatch:
            return "Facet userId does not match the signed-in user."
        case .invalidSchemaVersion(let v):
            return "Unsupported facet schemaVersion \(v); expected 1."
        }
    }
}

// MARK: - ContextStoreService

@MainActor
final class ContextStoreService: ObservableObject {

    static let shared = ContextStoreService()

    /// Current schema version for facets and snapshots written by this build.
    static let currentSchemaVersion = 1

    /// In-memory offline cache of the owner's facets. Mirrors Firestore after a load
    /// or a successful write. UI binds to this; it is never persisted off-device by
    /// this service beyond the owner's own Firestore docs.
    @Published private(set) var facets: [ContextFacet] = []
    @Published private(set) var isLoading = false

    private lazy var db = Firestore.firestore()

    private init() {}

    // MARK: - Gate / identity helpers

    /// Master gate. Every public method routes through this first.
    private func requireContextSystemEnabled() throws {
        guard AMENFeatureFlags.shared.contextSystemEnabled else {
            throw ContextStoreError.contextSystemDisabled
        }
    }

    private func requireUserId() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            throw ContextStoreError.notSignedIn
        }
        return uid
    }

    // MARK: - Firestore paths

    private func facetsCollection(_ uid: String) -> CollectionReference {
        db.collection("contextFacets").document(uid).collection("facets")
    }

    private func snapshotsCollection(_ uid: String) -> CollectionReference {
        db.collection("contextSnapshots").document(uid).collection("snapshots")
    }

    // MARK: - Factory

    /// Build a brand-new facet with the canonical tier from `ContextTierTable`,
    /// visibility defaulting to `.privateVisibility`, and schemaVersion 1.
    /// The tier is ALWAYS derived — callers may not set it by convention.
    func makeFacet(
        userId: String,
        category: FacetCategory,
        key: String,
        label: String,
        value: StructuredFacetValue,
        provenance: Provenance,
        visibility: Visibility = .privateVisibility,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> ContextFacet {
        ContextFacet(
            id: id,
            userId: userId,
            category: category,
            key: key,
            label: label,
            value: value,
            visibility: visibility,
            tier: ContextTierTable.tier(for: category, key: key),
            provenance: provenance,
            createdAt: createdAt,
            updatedAt: createdAt,
            schemaVersion: Self.currentSchemaVersion
        )
    }

    // MARK: - Write

    /// Persist a facet to `contextFacets/{uid}/facets/{facetId}`.
    /// Throws loudly on any guard failure; nothing reaches Firestore unless every
    /// invariant holds.
    func saveFacet(_ facet: ContextFacet) async throws {
        try requireContextSystemEnabled()
        let uid = try requireUserId()

        // Owner invariant — matches the rules layer.
        guard facet.userId == uid else { throw ContextStoreError.ownerMismatch }

        // Tier table is law.
        guard facet.hasValidTier else {
            throw ContextStoreError.invalidTier(
                expected: ContextTierTable.tier(for: facet.category, key: facet.key),
                actual: facet.tier
            )
        }

        // Schema version.
        guard facet.schemaVersion == Self.currentSchemaVersion else {
            throw ContextStoreError.invalidSchemaVersion(facet.schemaVersion)
        }

        // Approval before persistence (§1.7).
        guard facet.provenance.userApproved else { throw ContextStoreError.notApproved }

        // Aegis C59 sanitization receipt must verify.
        guard AegisEnforcementService.shared.verifySanitization(facet.provenance) else {
            throw ContextStoreError.sanitizationFailed
        }

        var toWrite = facet
        toWrite.updatedAt = Date()

        try facetsCollection(uid)
            .document(facet.id.uuidString)
            .setData(from: toWrite, merge: true)

        // Update offline cache (never logs facet values — only the id).
        upsertCache(toWrite)
        dlog("✅ ContextStore: saved facet \(facet.id.uuidString) [\(facet.tier.rawValue)]")
    }

    // MARK: - Read

    /// Load all of the owner's facets and refresh the offline cache.
    @discardableResult
    func loadFacets() async throws -> [ContextFacet] {
        try requireContextSystemEnabled()
        let uid = try requireUserId()

        isLoading = true
        defer { isLoading = false }

        let snap = try await facetsCollection(uid).getDocuments()
        let loaded: [ContextFacet] = snap.documents.compactMap { doc in
            do {
                return try doc.data(as: ContextFacet.self)
            } catch {
                dlog("⚠️ ContextStore: failed to decode facet \(doc.documentID): \(error)")
                return nil
            }
        }
        facets = loaded
        dlog("✅ ContextStore: loaded \(loaded.count) facets")
        return loaded
    }

    // MARK: - Delete

    func deleteFacet(id: UUID) async throws {
        try requireContextSystemEnabled()
        let uid = try requireUserId()

        try await facetsCollection(uid).document(id.uuidString).delete()
        facets.removeAll { $0.id == id }
        dlog("✅ ContextStore: deleted facet \(id.uuidString)")
    }

    // MARK: - Snapshots (append-only)

    /// Capture the current facet states as an immutable, append-only snapshot at
    /// `contextSnapshots/{uid}/snapshots/{id}`. Snapshots are never updated or deleted.
    @discardableResult
    func takeSnapshot(trigger: ContextSnapshot.Trigger) async throws -> ContextSnapshot {
        try requireContextSystemEnabled()
        let uid = try requireUserId()

        // Snapshot whatever is currently loaded. Callers wanting the freshest state
        // should loadFacets() first; we do not silently re-read to keep this an
        // explicit, deterministic capture of the in-memory cache.
        let states = facets
        let snapshot = ContextSnapshot(
            id: UUID(),
            userId: uid,
            takenAt: Date(),
            trigger: trigger,
            facetStates: states,
            schemaVersion: Self.currentSchemaVersion
        )

        // Append-only: create a new document; never overwrite an existing one.
        try snapshotsCollection(uid)
            .document(snapshot.id.uuidString)
            .setData(from: snapshot)

        dlog("✅ ContextStore: snapshot \(snapshot.id.uuidString) [\(trigger.rawValue)] with \(states.count) facets")
        return snapshot
    }

    // MARK: - Cache helpers

    private func upsertCache(_ facet: ContextFacet) {
        if let idx = facets.firstIndex(where: { $0.id == facet.id }) {
            facets[idx] = facet
        } else {
            facets.append(facet)
        }
    }
}
