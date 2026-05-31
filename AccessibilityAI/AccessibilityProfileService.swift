// AccessibilityProfileService.swift
// AMEN Universal Accessibility Engine — A8 Profile Persistence
// Firestore-backed accessibility profile read/write for a user.

import Foundation
import FirebaseFirestore

actor AccessibilityProfileService {
    static let shared = AccessibilityProfileService()
    private init() {}

    // MARK: - Firestore Path

    private func settingsRef(userId: String) -> DocumentReference {
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("settings")
            .document("accessibility")
    }

    // MARK: - Load

    /// Reads the accessibility profile from Firestore.
    /// Returns `AccessibilityProfile.default` when the document does not exist.
    func load(userId: String) async throws -> AccessibilityProfile {
        let snapshot = try await settingsRef(userId: userId).getDocument()
        guard snapshot.exists, let data = snapshot.data() else {
            return .default
        }
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let profile = try JSONDecoder().decode(AccessibilityProfile.self, from: jsonData)
        return profile
    }

    // MARK: - Save

    /// Encodes and upserts the full profile to Firestore.
    func save(_ profile: AccessibilityProfile, userId: String) async throws {
        let encoded = try JSONEncoder().encode(profile)
        guard let dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw AccessibilityProfileError.encodingFailed
        }
        try await settingsRef(userId: userId).setData(dict, merge: true)
    }

    // MARK: - Field-level Updates

    /// Array-union update: appends a new struggle term without overwriting existing ones.
    func addStruggleTerm(_ term: String, userId: String) async throws {
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        try await settingsRef(userId: userId).updateData([
            "struggleTerms": FieldValue.arrayUnion([term])
        ])
    }

    /// Patches the `reducedMotion` field without touching other profile fields.
    func syncReducedMotion(_ isReduced: Bool, userId: String) async throws {
        try await settingsRef(userId: userId).setData(
            ["reducedMotion": isReduced],
            merge: true
        )
    }
}

// MARK: - Errors

private enum AccessibilityProfileError: Error {
    case encodingFailed
}
