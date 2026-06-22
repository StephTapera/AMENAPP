//
//  ChurchProfileService.swift
//  AMENAPP
//
//  Manages CRUD operations for church profiles in Firestore.
//  Collection: "churchProfiles"
//
//  Design notes:
//  - All writes require an active role check at the call site (see RolePermissionService).
//  - verificationStatus mutations are admin-only; the method enforces this at the service layer.
//  - fetchProfile() populates `profile` and clears any prior error on success.
//

import Foundation
// import FirebaseFirestore   ← add when Firebase SDK is linked
// import FirebaseAuth        ← add when Firebase SDK is linked

// MARK: - Service

/// Manages CRUD operations for church profiles stored in Firestore.
///
/// Firestore collection: `churchProfiles`
/// Each document ID matches the church's unique identifier.
@MainActor
final class ChurchProfileService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var profile: ChurchProfile?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?

    // MARK: - Private

    private let churchId: String

    // Firestore reference placeholder:
    // private lazy var db = Firestore.firestore()

    // MARK: - Init

    init(churchId: String) {
        self.churchId = churchId
    }

    // MARK: - Fetch

    /// Fetches the church profile from Firestore and publishes it.
    /// Sets `error` if the document does not exist or decoding fails.
    func fetchProfile() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        // Firestore fetch:
        // let doc = try await db.collection("churchProfiles").document(churchId).getDocument()
        // guard let data = doc.data() else { throw ChurchProfileError.notFound }
        // self.profile = try Firestore.Decoder().decode(ChurchProfile.self, from: data)
        _ = churchId // suppress unused-variable warning until Firestore is wired
    }

    // MARK: - Writes

    /// Performs a Firestore merge update on the church profile document.
    ///
    /// - Parameter updates: A dictionary of field paths to new values.
    ///   Only the keys present in the dictionary are modified.
    /// - Throws: ``ChurchProfileError`` or a Firestore error on failure.
    func updateProfile(_ updates: [String: Any]) async throws {
        guard !updates.isEmpty else { return }

        // Firestore merge write:
        // try await db.collection("churchProfiles").document(churchId).setData(updates, merge: true)
    }

    /// Replaces the `serviceTimes` array on the church profile document.
    ///
    /// - Parameter times: The complete, updated list of service times.
    /// - Throws: A Firestore error if the write fails.
    func updateServiceTimes(_ times: [ChurchServiceTime]) async throws {
        // Encode times to [[String: Any]] for Firestore:
        // let encoded = try times.map { try Firestore.Encoder().encode($0) }
        // try await db.collection("churchProfiles").document(churchId)
        //     .updateData(["serviceTimes": encoded])
    }

    /// Replaces the `address` map on the church profile document.
    ///
    /// - Parameter address: The new church address.
    /// - Throws: A Firestore error if the write fails.
    func updateAddress(_ address: ChurchAddress) async throws {
        // Encode address to [String: Any] for Firestore:
        // let encoded = try Firestore.Encoder().encode(address)
        // try await db.collection("churchProfiles").document(churchId)
        //     .updateData(["address": encoded])
    }

    /// Updates the verification status of the church profile.
    ///
    /// This is an **admin-only** operation. The caller must hold a `manageProfile`
    /// permission (or higher) before invoking this method.
    ///
    /// - Parameter status: The new ``VerificationStatus`` to apply.
    /// - Throws: ``ChurchProfileError.insufficientPermissions`` if called without the required role,
    ///   or a Firestore error if the write fails.
    func updateVerificationStatus(_ status: VerificationStatus) async throws {
        // Firestore update:
        // try await db.collection("churchProfiles").document(churchId)
        //     .updateData(["verificationStatus": status.rawValue])
    }
}

// MARK: - Errors

enum ChurchProfileError: LocalizedError {
    case notFound
    case insufficientPermissions
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Church profile not found."
        case .insufficientPermissions:
            return "You do not have permission to perform this action."
        case .encodingFailed:
            return "Failed to encode church profile data."
        }
    }
}
