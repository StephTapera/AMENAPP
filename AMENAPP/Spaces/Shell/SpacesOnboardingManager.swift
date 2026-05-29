// SpacesOnboardingManager.swift
// AMENAPP — Spaces Onboarding
// Single source of truth for Spaces onboarding state.
// Firestore is authoritative (survives reinstall); UserDefaults is a fast local mirror.

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class SpacesOnboardingManager: ObservableObject {

    static let shared = SpacesOnboardingManager()

    // MARK: - State

    @Published var shouldShowOnboarding: Bool = false

    // MARK: - Constants

    private let currentVersion = 1
    private let udKey = "spaces.onboarding.completedVersion"

    // MARK: - Init

    private init() {}

    // MARK: - Resolve

    /// Call once when Spaces first appears. Returns after Firestore resolves.
    /// Fast path uses UserDefaults; slow path checks Firestore to survive reinstall.
    func resolve() async {
        // Fast path: UserDefaults cache
        let localVersion = UserDefaults.standard.integer(forKey: udKey)
        if localVersion >= currentVersion {
            shouldShowOnboarding = false
            return
        }

        // Slow path: Firestore (handles reinstall / fresh device)
        guard let uid = Auth.auth().currentUser?.uid else {
            shouldShowOnboarding = true
            return
        }

        do {
            let doc = try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("spaces").document("onboarding")
                .getDocument()
            let firestoreVersion = doc.data()?["completedVersion"] as? Int ?? 0
            if firestoreVersion >= currentVersion {
                // Firestore says done — sync local cache and skip onboarding
                UserDefaults.standard.set(currentVersion, forKey: udKey)
                shouldShowOnboarding = false
            } else {
                shouldShowOnboarding = true
            }
        } catch {
            dlog("⚠️ [SpacesOnboarding] Firestore check failed, defaulting to show: \(error)")
            shouldShowOnboarding = true
        }
    }

    // MARK: - Mark Complete

    /// Idempotent. Updates local state immediately; queues a background Firestore write.
    func markComplete() {
        UserDefaults.standard.set(currentVersion, forKey: udKey)
        shouldShowOnboarding = false

        // Background Firestore write — non-blocking, offline-safe
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            try? await Firestore.firestore()
                .collection("users").document(uid)
                .collection("spaces").document("onboarding")
                .setData([
                    "completedVersion": currentVersion,
                    "completedAt": Timestamp(date: Date())
                ], merge: true)
        }
    }

    // MARK: - Debug

#if DEBUG
    func resetForDebug() {
        UserDefaults.standard.removeObject(forKey: udKey)
        shouldShowOnboarding = false
        Task {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            try? await Firestore.firestore()
                .collection("users").document(uid)
                .collection("spaces").document("onboarding")
                .delete()
        }
    }
#endif
}
