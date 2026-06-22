//
//  AppCheckDebugProviderFactory.swift
//  AMENAPP
//
//  Created by Assistant on 2/4/26.
//
//  App Check provider factories for Firebase App Check.

import Foundation
import FirebaseAppCheck
import FirebaseCore

/// Debug provider factory for App Check.
/// Used in DEBUG builds (simulator and device) so engineers can register a
/// debug token in the Firebase Console without needing a real device attestation.
/// NEVER ship this class in a Release/production build — it is guarded by #if DEBUG
/// in AppDelegate and should only ever be referenced inside that guard.
class AppCheckDebugProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
        return AppCheckDebugProvider(app: app)
    }
}

/// AMEN App Check provider factory for production builds.
/// Uses App Attest on iOS 14+ (cryptographic device attestation).
/// Falls back to DeviceCheck on iOS 13 (device-level signal, weaker but broad).
final class AmenAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
        if #available(iOS 14.0, *) {
            return AppAttestProvider(app: app)
        } else {
            return DeviceCheckProvider(app: app)
        }
    }
}
