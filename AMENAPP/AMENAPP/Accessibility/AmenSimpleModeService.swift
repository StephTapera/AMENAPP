// AmenSimpleModeService.swift
// AMENAPP — Accessibility
//
// Observable service that owns the Simple Mode preference state.
// Persists locally via UserDefaults and syncs to Firestore when a user
// is signed in so the setting follows the account across installs.
//
// Design decisions:
//   • @Observable (Swift 5.9+, iOS 17+) — no Combine, no ObservableObject.
//   • All persist() mutations are synchronous (UserDefaults) + async (Firestore
//     via a detached Task so the caller's @Observable chain is never blocked).
//   • No force-unwraps.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - AmenSimpleModeService

@Observable
final class AmenSimpleModeService {

    // MARK: Singleton

    static let shared = AmenSimpleModeService()

    // MARK: Published state

    var isSimpleModeActive: Bool = false {
        didSet { persist() }
    }

    var fontScale: SimpleFontScale = .large {
        didSet { persist() }
    }

    var useHighContrast: Bool = false {
        didSet { persist() }
    }

    // MARK: Font scale enum

    enum SimpleFontScale: String, CaseIterable {
        case large
        case extraLarge

        var displayName: String {
            switch self {
            case .large:      return "Large"
            case .extraLarge: return "Extra Large"
            }
        }

        var dynamicTypeSize: DynamicTypeSize {
            switch self {
            case .large:      return .xLarge
            case .extraLarge: return .accessibility1
            }
        }
    }

    // MARK: UserDefaults keys

    private let defaults   = UserDefaults.standard
    private let kActive    = "simpleMode.active"
    private let kScale     = "simpleMode.fontScale"
    private let kContrast  = "simpleMode.highContrast"

    // MARK: Init

    private init() {
        load()
    }

    // MARK: Persistence

    private func load() {
        isSimpleModeActive = defaults.bool(forKey: kActive)
        fontScale = SimpleFontScale(rawValue: defaults.string(forKey: kScale) ?? "") ?? .large
        useHighContrast = defaults.bool(forKey: kContrast)
    }

    private func persist() {
        defaults.set(isSimpleModeActive, forKey: kActive)
        defaults.set(fontScale.rawValue, forKey: kScale)
        defaults.set(useHighContrast, forKey: kContrast)

        // Sync to Firestore when signed in (non-blocking detached task).
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let payload: [String: Any] = [
            "simpleModeActive":   isSimpleModeActive,
            "simpleFontScale":    fontScale.rawValue,
            "simpleHighContrast": useHighContrast
        ]
        Task.detached(priority: .utility) {
            try? await Firestore.firestore()
                .collection("users")
                .document(uid)
                .setData(payload, merge: true)
        }
    }
}
