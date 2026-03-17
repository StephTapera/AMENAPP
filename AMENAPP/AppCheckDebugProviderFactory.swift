//
//  AppCheckDebugProviderFactory.swift
//  AMENAPP
//
//  Created by Assistant on 2/4/26.
//
//  Debug provider for Firebase App Check in simulator

import Foundation
import FirebaseAppCheck
import FirebaseCore

/// Debug provider factory for App Check - use only in simulator
class AppCheckDebugProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        return AppCheckDebugProvider(app: app)
    }
}

/// App Attest provider factory for App Check - use on real devices
/// Firebase does not ship a dedicated AppAttestProviderFactory, so we define one here.
class AppCheckAppAttestProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        return AppAttestProvider(app: app)
    }
}

/// Extension to configure App Check based on environment
extension FirebaseApp {
    static func configureAppCheck() {
        #if targetEnvironment(simulator)
        // Simulator: use debug provider (requires registered debug token in Firebase Console)
        dlog("🔧 Configuring App Check with DEBUG provider (simulator)")
        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        #else
        // Real device: use App Attest
        dlog("🔧 Configuring App Check with App Attest provider (real device)")
        let providerFactory = AppCheckAppAttestProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        #endif
    }
}
