// QuietModePreferenceService.swift
// AMENAPP
//
// Persists the user's Quiet Mode (Church Focus) preference across sessions.
// Writes locally to UserDefaults immediately for snappy reads, and syncs to
// Firestore so the preference follows the user across devices.
//
// Preference options:
//   .auto  — AMEN silently enables Church Focus when confidence crosses 85
//   .ask   — AMEN shows a one-tap prompt when confidence crosses 60
//   .off   — AMEN never triggers Quiet Mode proactively
//
// Church-level override:
//   A per-church override stored in users/{uid}/churchPreferences/{churchId}
//   can suppress or force a specific mode for one church without changing the
//   global preference. Resolves as: church override ?? global preference.
//
// Firestore paths:
//   users/{uid}/churchPreferences/quietMode          → global preference
//   users/{uid}/churchPreferences/{churchId}_quietMode → per-church override

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - QuietModePreference

enum QuietModePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case ask
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .ask:  return "Ask"
        case .off:  return "Off"
        }
    }

    var subtitle: String {
        switch self {
        case .auto:
            return "AMEN quietly enables Church Focus when you arrive at service"
        case .ask:
            return "AMEN asks once before enabling quiet mode"
        case .off:
            return "You'll manage distractions on your own"
        }
    }

    var detailExplanation: String {
        switch self {
        case .auto:
            return "Using your location, calendar, and movement, AMEN will enable Church Focus automatically as you settle in for service — and disable it quietly when you leave."
        case .ask:
            return "When AMEN detects you're likely at church and in the service window, it will show a single notification asking if you'd like to enable quiet mode. One tap confirms."
        case .off:
            return "AMEN won't take any automatic quiet mode actions. You can always enable Focus manually in Control Center."
        }
    }

    var icon: String {
        switch self {
        case .auto: return "moon.stars.fill"
        case .ask:  return "bell.badge.fill"
        case .off:  return "bell.slash.fill"
        }
    }

    var accentColorName: String {
        switch self {
        case .auto: return "systemIndigo"
        case .ask:  return "systemOrange"
        case .off:  return "systemGray"
        }
    }
}

// MARK: - Service

@MainActor
final class QuietModePreferenceService: ObservableObject {

    static let shared = QuietModePreferenceService()

    private let globalKey = "amen.quietMode.preference"
    // GAP P0-5: explicit consent gate for the background sensing pipeline (location +
    // CoreMotion + calendar correlation). The user must tap through the QuietMode
    // onboarding sheet before ChurchProximityEngine.startMonitoring() runs for the
    // first time. Stored in UserDefaults so it persists across launches.
    private let consentKey = "amen.quietMode.proximityConsent"
    private let db = Firestore.firestore()

    @Published private(set) var preference: QuietModePreference = .ask
    @Published private(set) var isSyncing = false

    /// True iff the user has explicitly opted into attendance-sensing (Quiet Mode onboarding).
    var hasGrantedProximityConsent: Bool {
        UserDefaults.standard.bool(forKey: consentKey)
    }

    /// Call this when the user completes QuietMode onboarding (opt-in confirmed).
    func grantProximityConsent() {
        UserDefaults.standard.set(true, forKey: consentKey)
    }

    /// Call this if the user revokes consent (e.g., from Settings → Quiet Mode → Off).
    func revokeProximityConsent() {
        UserDefaults.standard.removeObject(forKey: consentKey)
    }

    private init() {
        loadFromUserDefaults()
    }

    // MARK: - Read

    private func loadFromUserDefaults() {
        if let raw = UserDefaults.standard.string(forKey: globalKey),
           let pref = QuietModePreference(rawValue: raw) {
            preference = pref
        }
    }

    /// Pull the latest preference from Firestore (call once on sign-in).
    func syncFromRemote() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let snap = try? await db
            .collection("users").document(uid)
            .collection("churchPreferences").document("quietMode")
            .getDocument()
        else { return }

        if let raw = snap.data()?["preference"] as? String,
           let pref = QuietModePreference(rawValue: raw) {
            preference = pref
            UserDefaults.standard.set(raw, forKey: globalKey)
        }
    }

    // MARK: - Write (Global)

    func setPreference(_ pref: QuietModePreference) {
        preference = pref
        UserDefaults.standard.set(pref.rawValue, forKey: globalKey)
        writeGlobalToFirestore(pref)
    }

    private func writeGlobalToFirestore(_ pref: QuietModePreference) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSyncing = true
        Task {
            defer { isSyncing = false }
            try? await db
                .collection("users").document(uid)
                .collection("churchPreferences").document("quietMode")
                .setData([
                    "preference": pref.rawValue,
                    "updatedAt": FieldValue.serverTimestamp(),
                ], merge: true)
        }
    }

    // MARK: - Church-Level Override

    /// Returns the effective preference for a specific church —
    /// church override if present, otherwise the global preference.
    func effectivePreference(for churchId: String) async -> QuietModePreference {
        guard let uid = Auth.auth().currentUser?.uid else { return preference }
        let overrideKey = "\(churchId)_quietMode"
        guard let snap = try? await db
            .collection("users").document(uid)
            .collection("churchPreferences").document(overrideKey)
            .getDocument(),
              let raw = snap.data()?["preference"] as? String,
              let override = QuietModePreference(rawValue: raw)
        else {
            return preference
        }
        return override
    }

    /// Saves a per-church override that takes precedence over the global preference.
    func setOverride(_ pref: QuietModePreference, for churchId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let overrideKey = "\(churchId)_quietMode"
        try? await db
            .collection("users").document(uid)
            .collection("churchPreferences").document(overrideKey)
            .setData([
                "preference": pref.rawValue,
                "churchId": churchId,
                "updatedAt": FieldValue.serverTimestamp(),
            ], merge: true)
    }

    /// Removes a per-church override, reverting to the global preference.
    func clearOverride(for churchId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let overrideKey = "\(churchId)_quietMode"
        try? await db
            .collection("users").document(uid)
            .collection("churchPreferences").document(overrideKey)
            .delete()
    }

    // MARK: - Has Completed Onboarding

    private let onboardingKey = "amen.quietMode.onboardingComplete"

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: onboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingKey) }
    }

    func markOnboardingComplete() {
        hasCompletedOnboarding = true
    }
}
