// BiometricAppLockManager.swift
// AMENAPP
//
// App-lock gate: locks the app when it enters the background (if biometric
// auth is enabled in settings) and shows a fullscreen lock gate on resume.
// Intentionally minimal — no UserDefaults, no scene-phase listeners, no analytics.
// Scene-phase wiring lives in ContentView.handleScenePhaseChange.

import Foundation
import LocalAuthentication

@MainActor
final class BiometricAppLockManager: ObservableObject {

    // MARK: - Singleton

    static let shared = BiometricAppLockManager()
    private init() {}

    // MARK: - Published state

    @Published private(set) var isAppLocked = false

    // MARK: - Private

    private let biometricService = BiometricAuthService.shared

    // MARK: - Public API

    /// Lock the app. No-ops when biometric auth is not enabled in Settings.
    func lockIfEnabled() {
        guard biometricService.isBiometricEnabled else { return }
        isAppLocked = true
    }

    /// Attempt to unlock with biometrics. Calls `BiometricAuthService.authenticate(reason:)`
    /// which returns `Bool` (never throws to the caller). No-ops when already unlocked.
    func unlockWithBiometrics() async {
        guard isAppLocked else { return }
        let success = await biometricService.authenticate(reason: "Unlock AMEN")
        if success {
            isAppLocked = false
        }
    }
}
