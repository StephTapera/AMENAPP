// FindChurch2SeekerProfileService.swift
// AMENAPP — Find Church 2.0 · Wave 3
//
// Manages SeekerProfile: on-device storage (UserDefaults + keychain key),
// optional Firestore sync when privacySyncEnabled == true.
//
// Gate: AMENFeatureFlags.shared.findChurch2OnboardingEnabled
// If the flag is OFF the profile stays .empty and no persistence occurs.

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - FindChurch2SeekerProfileService

@MainActor
final class FindChurch2SeekerProfileService: ObservableObject {

    // MARK: Published state

    @Published var profile: SeekerProfile = .empty

    // MARK: Private constants

    private let userDefaultsKey = "fc2_seeker_profile"
    private let db = Firestore.firestore()

    // MARK: Init

    init() {}

    // MARK: - Load

    /// Reads from UserDefaults key "fc2_seeker_profile" (JSON encoded).
    /// Falls back to .empty if the flag is off, the key is absent, or decoding fails.
    func loadProfile() async {
        guard AMENFeatureFlags.shared.findChurch2OnboardingEnabled else {
            profile = .empty
            return
        }

        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            profile = .empty
            return
        }

        do {
            let decoded = try JSONDecoder().decode(SeekerProfile.self, from: data)
            profile = decoded
        } catch {
            // Corrupted or schema-migrated data — reset gracefully.
            profile = .empty
        }
    }

    // MARK: - Save

    /// Encodes the given profile to UserDefaults.
    /// If privacySyncEnabled is true, also writes to Firestore seekerProfiles/{uid}.
    /// No-op if the feature flag is off.
    func saveProfile(_ updatedProfile: SeekerProfile) async {
        guard AMENFeatureFlags.shared.findChurch2OnboardingEnabled else { return }

        // Persist locally first — always.
        do {
            let data = try JSONEncoder().encode(updatedProfile)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            // Encoding failure is non-fatal; log and continue.
            return
        }

        // Update published property.
        profile = updatedProfile

        // Optional Firestore sync.
        guard updatedProfile.privacySyncEnabled else { return }

        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }

        do {
            let encoded = try Firestore.Encoder().encode(updatedProfile)
            try await db.collection("seekerProfiles").document(uid).setData(encoded, merge: true)
        } catch {
            // Cloud sync is best-effort; local copy is already written.
        }
    }

    // MARK: - Apply Onboarding

    /// Updates the profile from the three onboarding phases and immediately saves.
    /// Functional privacy flags are applied from comfortChips via applyComfortChips(_:).
    func applyOnboarding(
        intents: [SeekerProfile.SeekerIntent],
        fitChips: [SeekerProfile.FitChip],
        comfortChips: [SeekerProfile.ComfortChip]
    ) {
        guard AMENFeatureFlags.shared.findChurch2OnboardingEnabled else { return }

        var updated = profile
        updated.intent = intents
        updated.fitChips = fitChips
        updated.comfortPreferences = comfortChips
        updated.updatedAt = Date()

        // Apply functional flags embedded in comfort chips.
        updated = applyComfortFlags(to: updated, chips: comfortChips)

        Task { [weak self] in await self?.saveProfile(updated) }
    }

    // MARK: - Apply Comfort Chips (functional flags)

    /// Sets functional privacy flags based on the provided comfort chips.
    /// - .noLocation  → profile.dontShareLocation = true
    /// - .privateRecs → profile.privateRecommendationsOnly = true
    func applyComfortChips(_ chips: [SeekerProfile.ComfortChip]) {
        guard AMENFeatureFlags.shared.findChurch2OnboardingEnabled else { return }

        var updated = profile
        updated = applyComfortFlags(to: updated, chips: chips)
        updated.updatedAt = Date()

        Task { [weak self] in await self?.saveProfile(updated) }
    }

    // MARK: - Reset

    /// Clears UserDefaults key and deletes the Firestore document if sync was active.
    func resetProfile() async {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        profile = .empty

        // Delete Firestore document if we were syncing.
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }

        do {
            try await db.collection("seekerProfiles").document(uid).delete()
        } catch {
            // Best-effort; local data is already cleared.
        }
    }

    // MARK: - Private helpers

    /// Pure function: applies .noLocation and .privateRecs flags to a copy of the profile.
    private func applyComfortFlags(
        to source: SeekerProfile,
        chips: [SeekerProfile.ComfortChip]
    ) -> SeekerProfile {
        var updated = source

        if chips.contains(.noLocation) {
            updated.dontShareLocation = true
        }

        if chips.contains(.privateRecs) {
            updated.privateRecommendationsOnly = true
        }

        return updated
    }
}
