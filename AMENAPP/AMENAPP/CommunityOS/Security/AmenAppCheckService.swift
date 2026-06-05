//
//  AmenAppCheckService.swift
//  AMENAPP
//
//  Phase 4 — Security Foundation: iOS App Check enforcement service.
//  Registers the DeviceCheck provider for production builds and the
//  Debug provider for simulator/debug builds.
//
//  Usage:
//    1. Call AmenAppCheckService.configure() in your AppDelegate or
//       App.init() BEFORE FirebaseApp.configure().
//    2. Call AmenAppCheckService.getToken() before sensitive backend
//       calls that require additional client attestation.
//
//  DEPLOY: firestore.rules must be deployed with:
//    firebase deploy --only firestore:rules --project amen-5e359
//    by a human before security is active.
//
//  NOTE: App Check token enforcement must also be enabled in the
//  Firebase Console (App Check → AMEN → Enforce) before tokens
//  are required by Cloud Functions. Do this AFTER rolling out this
//  build to avoid locking out existing users.
//

import Foundation
import FirebaseCore
import FirebaseAppCheck

// MARK: - AmenAppCheckService

/// Singleton service that manages Firebase App Check configuration
/// and token retrieval for the AMEN platform.
///
/// App Check adds a security layer that verifies requests to Firebase
/// backends originate from legitimate, unmodified AMEN app instances.
///
/// Thread safety: All async methods are safe to call from any actor.
final class AmenAppCheckService {

    // MARK: - Shared Instance

    static let shared = AmenAppCheckService()
    private init() {}

    // MARK: - Configuration

    /// Configure App Check at application startup.
    ///
    /// Must be called BEFORE `FirebaseApp.configure()` in your app entry point.
    ///
    /// - In DEBUG / Simulator builds: uses `AppCheckDebugProvider` which logs
    ///   a debug token to the console. Add this token to the Firebase Console
    ///   under App Check → Apps → Add debug token.
    /// - In RELEASE / device builds: uses `DeviceCheckProviderFactory` which
    ///   uses Apple's DeviceCheck framework to generate a hardware-attested token.
    ///
    /// Example (App.swift):
    /// ```swift
    /// @main
    /// struct AMENAPPApp: App {
    ///     init() {
    ///         AmenAppCheckService.configure()
    ///         FirebaseApp.configure()
    ///     }
    /// }
    /// ```
    static func configure() {
#if DEBUG
        // Debug / Simulator: use the debug provider.
        // The debug token is printed to the Xcode console on first launch.
        // Register it at: Firebase Console → App Check → <your app> → Manage debug tokens.
        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
#else
        // Production / TestFlight / device: use Apple DeviceCheck.
        // DeviceCheck uses a device-level key pair to attest the app is genuine.
        // Requires: DeviceCheck capability enabled in Xcode (Signing & Capabilities).
        let providerFactory = DeviceCheckProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
#endif
    }

    // MARK: - Token Retrieval

    /// Returns a valid App Check token string for use in backend calls.
    ///
    /// Tokens are automatically cached and refreshed by the Firebase SDK.
    /// This method forces a fresh token fetch; prefer using it only when
    /// you need to attach the token to a non-Firebase HTTP request.
    /// Firebase callable functions handle App Check automatically when
    /// `enforceAppCheck: true` is set on the Cloud Function.
    ///
    /// - Throws: `AppCheckError` if the provider is unavailable (e.g., device
    ///   does not support DeviceCheck) or if the token exchange fails.
    /// - Returns: A JWT string representing the App Check token.
    static func getToken() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            AppCheck.appCheck().token(forcingRefresh: false) { token, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let token = token {
                    continuation.resume(returning: token.token)
                } else {
                    continuation.resume(
                        throwing: AmenAppCheckError.tokenUnavailable(
                            "App Check returned nil token without an error"
                        )
                    )
                }
            }
        }
    }

    // MARK: - Convenience

    /// Returns `true` if the device can produce a valid App Check token.
    ///
    /// In production this indicates the device supports Apple DeviceCheck.
    /// In debug builds this is always `true` (debug provider always succeeds).
    ///
    /// This is a best-effort check — use it for UI gating only, not for
    /// security decisions (security decisions live in Cloud Functions).
    static func isDeviceAttested() async -> Bool {
        do {
            let token = try await getToken()
            return !token.isEmpty
        } catch {
            // Log but do not surface to user — App Check failure is non-fatal
            // for the user experience; backend enforcement handles denial.
#if DEBUG
            print("[AmenAppCheck] Device attestation check failed: \(error.localizedDescription)")
#endif
            return false
        }
    }

    // MARK: - Token for Manual Header Attachment
    //
    // Use this when calling a Cloud Run endpoint or non-Firebase HTTP API
    // that reads the X-Firebase-AppCheck header for server-side validation.
    //
    // Example:
    //   var request = URLRequest(url: url)
    //   if let header = try? await AmenAppCheckService.tokenHeader() {
    //       request.setValue(header, forHTTPHeaderField: "X-Firebase-AppCheck")
    //   }

    /// Returns the App Check token formatted as an HTTP header value.
    /// - Throws: Same as `getToken()`.
    static func tokenHeader() async throws -> String {
        return try await getToken()
    }
}

// MARK: - AmenAppCheckError

/// Errors specific to the AMEN App Check service.
enum AmenAppCheckError: LocalizedError {
    case tokenUnavailable(String)
    case deviceCheckNotSupported

    var errorDescription: String? {
        switch self {
        case .tokenUnavailable(let reason):
            return "App Check token unavailable: \(reason)"
        case .deviceCheckNotSupported:
            return "This device does not support Apple DeviceCheck. App Check attestation is unavailable."
        }
    }
}
