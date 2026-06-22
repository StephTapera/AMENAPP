// BereanAIConsentManager.swift
// AMENAPP
//
// PRIV-005 fix: first-run AI consent gate for Berean.
//
// Berean is a generative-AI surface. Apple App Review practice and the EU AI Act
// require an explicit, informed first-run consent before any AI processing of the
// user's input begins. This manager is the single source of truth for whether the
// current user has granted that consent.
//
// Pattern mirrors BereanDMConsentSheet / GDPRConsentView:
//   - UserDefaults for fast, synchronous in-process checks (the pipeline hard-gate).
//   - Firestore mirror for cross-device persistence + an audit trail.
//
// Fail-closed: when consent is unknown, hasConsented == false and the pipeline
// refuses to call the model. There is no flag to silently disable the gate.

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class BereanAIConsentManager: ObservableObject {

    static let shared = BereanAIConsentManager()

    /// UserDefaults key for the granted flag. Versioned so a future disclosure
    /// revision can re-prompt without colliding with the old value.
    private static let grantedKey = "bereanAIConsentGranted_v1"

    /// Current disclosure version recorded alongside consent for audit.
    static let consentVersion = "1.0"

    /// Published so views can present the disclosure sheet reactively.
    @Published var hasConsented: Bool

    private init() {
        self.hasConsented = UserDefaults.standard.bool(forKey: Self.grantedKey)
    }

    /// Synchronous check used by the pipeline hard-gate. Reads UserDefaults directly
    /// so it is valid even before this object has been observed by a view.
    static func hasConsentedNow() -> Bool {
        UserDefaults.standard.bool(forKey: grantedKey)
    }

    /// Persists the user's choice to UserDefaults (fast) and Firestore (audit trail).
    /// Throws if the Firestore write fails so the caller can withhold dismissal until
    /// the record is durably saved.
    func recordConsent(_ granted: Bool) async throws {
        UserDefaults.standard.set(granted, forKey: Self.grantedKey)
        hasConsented = granted

        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("⚠️ [BereanAIConsent] No authenticated user — skipped Firestore write.")
            return
        }
        try await Firestore.firestore().collection("users").document(uid).setData(
            [
                "bereanAIConsentGranted": granted,
                "bereanAIConsentDate": Timestamp(),
                "bereanAIConsentVersion": Self.consentVersion
            ],
            merge: true
        )
    }
}
