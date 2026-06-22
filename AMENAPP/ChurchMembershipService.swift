//
//  ChurchMembershipService.swift
//  AMENAPP
//
//  Manages church membership relationships between users and churches.
//  Collection: "churchMemberships"
//
//  Privacy rules:
//  - Member lists are NEVER publicly exposed via this service.
//  - Public-facing aggregation (mutual signals) is handled exclusively
//    by ChurchMutualsService, which filters on VisibilityLevel.
//  - Leaving a church performs a soft delete (status → "inactive") so
//    historical relationship data is preserved for the user's own records.
//

import Foundation
// import FirebaseFirestore   ← add when Firebase SDK is linked
// import FirebaseAuth        ← add when Firebase SDK is linked

// MARK: - Service

/// Manages church membership relationships.
///
/// Firestore collection: `churchMemberships`
///
/// Each document represents a single user–church affiliation and carries
/// the user's chosen `VisibilityLevel`, which gates all public surfaces.
@MainActor
final class ChurchMembershipService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var userMemberships: [ChurchMembership] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?

    // Firestore reference placeholder:
    // private lazy var db = Firestore.firestore()

    // MARK: - Fetch

    /// Fetches all memberships for a given user and publishes them to `userMemberships`.
    ///
    /// Queries `churchMemberships` where `userId == userId` and
    /// `status == "active"`, ordered by `joinedAt` descending.
    ///
    /// - Parameter userId: The UID of the user whose memberships to load.
    func fetchMemberships(for userId: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        // Firestore query:
        // let snapshot = try await db.collection("churchMemberships")
        //     .whereField("userId", isEqualTo: userId)
        //     .whereField("status", isEqualTo: "active")
        //     .order(by: "joinedAt", descending: true)
        //     .getDocuments()
        // self.userMemberships = try snapshot.documents.map {
        //     try Firestore.Decoder().decode(ChurchMembership.self, from: $0.data())
        // }
        _ = userId // suppress unused-variable warning until Firestore is wired
    }

    // MARK: - Writes

    /// Creates a new membership document and returns the resulting ``ChurchMembership``.
    ///
    /// Default visibility is `.mutualsOnly` to protect member privacy until the user
    /// explicitly opts into a more open setting.
    ///
    /// - Parameters:
    ///   - userId: UID of the user joining.
    ///   - churchId: ID of the church being joined.
    ///   - relationship: The nature of the user's connection (e.g. `.attends`, `.member`).
    ///   - visibility: Controls who can see this membership. Defaults to `.mutualsOnly`.
    /// - Returns: The newly created ``ChurchMembership``.
    /// - Throws: A Firestore error if the write fails.
    func joinChurch(
        userId: String,
        churchId: String,
        relationship: ChurchRelationshipType,
        visibility: VisibilityLevel = .mutualsOnly
    ) async throws -> ChurchMembership {
        // Build membership payload:
        // let docRef = db.collection("churchMemberships").document()
        // let membership = ChurchMembership(
        //     id: docRef.documentID,
        //     userId: userId,
        //     churchId: churchId,
        //     relationshipType: relationship,
        //     visibility: visibility,
        //     displayOnProfile: false,
        //     isPrimaryChurch: false,
        //     joinedAt: Date(),
        //     source: "user",
        //     status: "active"
        // )
        // let encoded = try Firestore.Encoder().encode(membership)
        // try await docRef.setData(encoded)
        // return membership

        // Stub — replace with Firestore implementation above.
        throw ChurchMembershipError.notImplemented
    }

    /// Updates the visibility level of an existing membership document.
    ///
    /// - Parameters:
    ///   - membershipId: The Firestore document ID of the membership.
    ///   - visibility: The new ``VisibilityLevel`` to apply.
    /// - Throws: A Firestore error if the write fails.
    func updateVisibility(membershipId: String, visibility: VisibilityLevel) async throws {
        // Firestore update:
        // try await db.collection("churchMemberships").document(membershipId)
        //     .updateData(["visibility": visibility.rawValue])
    }

    /// Sets whether this membership appears on the user's public profile card.
    ///
    /// - Parameters:
    ///   - membershipId: The Firestore document ID of the membership.
    ///   - display: `true` to show on profile; `false` to hide.
    /// - Throws: A Firestore error if the write fails.
    func updateDisplayOnProfile(membershipId: String, display: Bool) async throws {
        // Firestore update:
        // try await db.collection("churchMemberships").document(membershipId)
        //     .updateData(["displayOnProfile": display])
    }

    /// Marks a membership as the user's primary church.
    ///
    /// Clears `isPrimaryChurch` on any existing primary membership for this user
    /// before setting the new one, maintaining a single-primary invariant.
    ///
    /// - Parameters:
    ///   - membershipId: The document ID of the membership to promote.
    ///   - userId: The UID of the user, used to scope the clear query.
    /// - Throws: A Firestore error if any write in the batch fails.
    func setPrimaryChurch(membershipId: String, userId: String) async throws {
        // Batched Firestore write:
        // let batch = db.batch()
        //
        // Clear existing primary:
        // let existingSnapshot = try await db.collection("churchMemberships")
        //     .whereField("userId", isEqualTo: userId)
        //     .whereField("isPrimaryChurch", isEqualTo: true)
        //     .getDocuments()
        // for doc in existingSnapshot.documents {
        //     batch.updateData(["isPrimaryChurch": false], forDocument: doc.reference)
        // }
        //
        // Set new primary:
        // let newRef = db.collection("churchMemberships").document(membershipId)
        // batch.updateData(["isPrimaryChurch": true], forDocument: newRef)
        //
        // try await batch.commit()
    }

    /// Soft-deletes a membership by setting its `status` field to `"inactive"`.
    ///
    /// The document is retained so the user retains their notes and history
    /// associated with that church.
    ///
    /// - Parameter membershipId: The Firestore document ID of the membership to leave.
    /// - Throws: A Firestore error if the write fails.
    func leaveChurch(membershipId: String) async throws {
        // Firestore soft delete:
        // try await db.collection("churchMemberships").document(membershipId)
        //     .updateData(["status": "inactive", "leftAt": FieldValue.serverTimestamp()])
    }
}

// MARK: - Errors

enum ChurchMembershipError: LocalizedError {
    case notFound
    case alreadyMember
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Membership not found."
        case .alreadyMember:
            return "You are already connected to this church."
        case .notImplemented:
            return "This operation is not yet implemented."
        }
    }
}
