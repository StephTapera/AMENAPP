// AccessibilityProfileService.swift
// AMEN Universal Accessibility Engine — A4 Reading & Narration
// Persists and syncs the user's AccessibilityProfile to Firestore.
// Exposes an ObservableObject bridge so SwiftUI views can bind to the profile.

import Foundation
import FirebaseFirestore

// MARK: - AccessibilityProfileService (actor)

actor AccessibilityProfileService {

    // MARK: Shared Instance

    static let shared = AccessibilityProfileService()
    private init() {}

    // MARK: Published Profile (actor-isolated backing)

    /// Actor-isolated source of truth. Updated on every successful load/save.
    /// SwiftUI views observe `AccessibilityProfileBridge.shared.profile` instead.
    private(set) var profile: AccessibilityProfile = .default

    // MARK: Firestore Path

    private let db = Firestore.firestore()

    private func document(userId: String) -> DocumentReference {
        db.collection("users")
          .document(userId)
          .collection("settings")
          .document("accessibility")
    }

    // MARK: - Load

    /// Reads `users/{userId}/settings/accessibility` and decodes it into an
    /// `AccessibilityProfile`. Falls back to `.default` when the document is
    /// absent or decoding fails; updates the in-memory copy on MainActor.
    func loadProfile(userId: String) async throws {
        guard !userId.isEmpty else {
            throw AccessibilityProfileError.invalidUserId
        }
        let snap = try await document(userId: userId).getDocument()
        guard snap.exists, let raw = snap.data() else {
            // No stored profile yet — keep default; nothing to decode.
            return
        }
        let decoded: AccessibilityProfile
        do {
            let data = try JSONSerialization.data(withJSONObject: raw)
            decoded = try JSONDecoder().decode(AccessibilityProfile.self, from: data)
        } catch {
            throw AccessibilityProfileError.decodingFailed
        }
        profile = decoded
        await publishToMainActor(decoded)
    }

    // MARK: - Save

    /// Encodes and upserts the full profile to Firestore, then updates
    /// the in-memory copy.
    func saveProfile(_ newProfile: AccessibilityProfile, userId: String) async throws {
        guard !userId.isEmpty else {
            throw AccessibilityProfileError.invalidUserId
        }
        let encoded: [String: Any]
        do {
            let data = try JSONEncoder().encode(newProfile)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AccessibilityProfileError.encodingFailed
            }
            encoded = dict
        } catch is AccessibilityProfileError {
            throw AccessibilityProfileError.encodingFailed
        }
        try await document(userId: userId).setData(encoded, merge: true)
        profile = newProfile
        await publishToMainActor(newProfile)
    }

    // MARK: - Field-level Update

    /// Updates a single field on the current in-memory profile and persists
    /// the result. Use the `profile` property for the current state before
    /// calling this.
    func update<T>(
        _ keyPath: WritableKeyPath<AccessibilityProfile, T>,
        to value: T,
        userId: String
    ) async throws {
        var updated = profile
        updated[keyPath: keyPath] = value
        try await saveProfile(updated, userId: userId)
    }

    // MARK: - Private Helpers

    @MainActor
    private func publishToMainActor(_ p: AccessibilityProfile) {
        AccessibilityProfileBridge.shared.accept(p)
    }
}

// MARK: - AccessibilityProfileBridge (MainActor / ObservableObject)

/// Thin MainActor observable that mirrors the actor-isolated profile so
/// SwiftUI views can bind without crossing concurrency boundaries themselves.
@MainActor
final class AccessibilityProfileBridge: ObservableObject {

    static let shared = AccessibilityProfileBridge()
    private init() {}

    @Published private(set) var profile: AccessibilityProfile = .default

    /// Called only from `AccessibilityProfileService` via its MainActor hop.
    fileprivate func accept(_ p: AccessibilityProfile) {
        profile = p
    }
}

// MARK: - Errors

enum AccessibilityProfileError: LocalizedError {
    case invalidUserId
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidUserId:   return "A valid user ID is required."
        case .encodingFailed:  return "Failed to encode the accessibility profile."
        case .decodingFailed:  return "Failed to decode the accessibility profile."
        }
    }
}
