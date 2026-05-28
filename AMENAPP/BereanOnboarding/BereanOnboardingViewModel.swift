// BereanOnboardingManager.swift (stored as BereanOnboardingViewModel.swift)
// AMENAPP — Berean Onboarding
// Single source of truth for Berean onboarding state.
// Firestore is authoritative (survives reinstall); UserDefaults is a fast local mirror.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class BereanOnboardingManager: ObservableObject {

    static let shared = BereanOnboardingManager()

    // MARK: - Presentation Decision

    enum Presentation: Equatable {
        case loading        // Firestore not yet resolved; caller shows skeleton
        case none           // No interstitial needed
        case fullOnboarding // First time or version bump
        case welcomeBack    // Completed + inactive 7+ days, or first post-reinstall launch
    }

    @Published private(set) var presentation: Presentation = .loading

    // MARK: - Constants

    static let currentVersion = 1
    private let inactiveDays: TimeInterval = 7 * 86_400

    // MARK: - UserDefaults keys

    private enum UDKey {
        static let version          = "berean.onboarding.version"
        static let completedAt      = "berean.onboarding.completedAt"
        static let lastActive       = "berean.onboarding.lastActiveAt"
        static let welcomeBackShown = "berean.onboarding.welcomeBackShown"
        // Legacy — read for migration, never write
        static let legacyV1 = "bereanOnboardingComplete"
        static let legacyV3 = "berean_onboarding_completed_v3"
    }

    private var activityTask: Task<Void, Never>?

    private init() {}

    // MARK: - Resolve

    /// Call once when the Berean feature first appears. Returns after Firestore resolves.
    func resolve() async {
        presentation = .loading

        let localDecision = localEvaluation()

        guard let uid = Auth.auth().currentUser?.uid else {
            presentation = localDecision ?? .fullOnboarding
            return
        }

        do {
            let doc = try await Firestore.firestore()
                .collection("users").document(uid)
                .getDocument()
            let berean = doc.data().flatMap { $0["berean"] as? [String: Any] }
            let remoteVersion    = berean?["onboardingCompletedVersion"] as? Int
            let remoteLastActive = (berean?["lastActiveAt"] as? Timestamp)?.dateValue()

            // Mirror authoritative Firestore values to the local cache
            if let v = remoteVersion    { UserDefaults.standard.set(v, forKey: UDKey.version)    }
            if let d = remoteLastActive { UserDefaults.standard.set(d, forKey: UDKey.lastActive) }

            let hadLocalCache = localDecision != nil
            let isReinstall   = !hadLocalCache && remoteVersion != nil

            presentation = decide(
                completedVersion: remoteVersion,
                lastActiveAt: remoteLastActive,
                isReinstall: isReinstall
            )
        } catch {
            // Network unavailable — fall back to local cache
            presentation = localDecision ?? .fullOnboarding
        }
    }

    // MARK: - Mark Complete

    /// Idempotent. Sets local state immediately; queues Firestore write (offline-safe).
    func markComplete() {
        guard presentation == .fullOnboarding || presentation == .welcomeBack else { return }

        let now = Date()
        UserDefaults.standard.set(Self.currentVersion, forKey: UDKey.version)
        UserDefaults.standard.set(now,  forKey: UDKey.completedAt)
        UserDefaults.standard.set(now,  forKey: UDKey.lastActive)
        UserDefaults.standard.set(true, forKey: UDKey.welcomeBackShown)
        UserDefaults.standard.set(true, forKey: UDKey.legacyV1)
        presentation = .none

        Task {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            try? await Firestore.firestore()
                .collection("users").document(uid)
                .setData([
                    "berean": [
                        "onboardingCompletedVersion": BereanOnboardingManager.currentVersion,
                        "onboardingCompletedAt":      FieldValue.serverTimestamp(),
                        "lastActiveAt":               FieldValue.serverTimestamp()
                    ]
                ], merge: true)
        }
    }

    /// Acknowledges the Welcome Back screen without re-running the full onboarding.
    func markWelcomeBackSeen() {
        UserDefaults.standard.set(true, forKey: UDKey.welcomeBackShown)
        presentation = .none

        Task {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            try? await Firestore.firestore()
                .collection("users").document(uid)
                .setData(["berean": ["lastActiveAt": FieldValue.serverTimestamp()]], merge: true)
        }
    }

    // MARK: - Activity Tracking

    /// Debounced: fires Firestore write at most once per Berean session.
    func recordActivity() {
        activityTask?.cancel()
        activityTask = Task {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            UserDefaults.standard.set(Date(), forKey: UDKey.lastActive)
            try? await Firestore.firestore()
                .collection("users").document(uid)
                .setData(["berean": ["lastActiveAt": FieldValue.serverTimestamp()]], merge: true)
        }
    }

    // MARK: - Debug

#if DEBUG
    func resetForDebug() {
        [UDKey.version, UDKey.completedAt, UDKey.lastActive,
         UDKey.welcomeBackShown, UDKey.legacyV1, UDKey.legacyV3].forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
        presentation = .loading
        Task {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            try? await Firestore.firestore()
                .collection("users").document(uid)
                .updateData([
                    "berean.onboardingCompletedVersion": FieldValue.delete(),
                    "berean.onboardingCompletedAt":      FieldValue.delete(),
                    "berean.lastActiveAt":               FieldValue.delete()
                ])
        }
    }
#endif

    // MARK: - Private

    private func localEvaluation() -> Presentation? {
        let legacyDone = UserDefaults.standard.bool(forKey: UDKey.legacyV1)
            || UserDefaults.standard.bool(forKey: UDKey.legacyV3)

        let version: Int?
        if let v = UserDefaults.standard.object(forKey: UDKey.version) as? Int {
            version = v
        } else if legacyDone {
            version = 0 // treat any legacy completion as pre-current version
        } else {
            return nil  // no local data — defer to Firestore
        }

        let lastActive = UserDefaults.standard.object(forKey: UDKey.lastActive) as? Date
        return decide(completedVersion: version, lastActiveAt: lastActive, isReinstall: false)
    }

    private func decide(
        completedVersion: Int?,
        lastActiveAt: Date?,
        isReinstall: Bool
    ) -> Presentation {
        guard let version = completedVersion else { return .fullOnboarding }
        guard version >= Self.currentVersion else { return .fullOnboarding }

        if isReinstall && !UserDefaults.standard.bool(forKey: UDKey.welcomeBackShown) {
            return .welcomeBack
        }
        if let last = lastActiveAt, Date().timeIntervalSince(last) > inactiveDays {
            return .welcomeBack
        }
        return .none
    }
}
