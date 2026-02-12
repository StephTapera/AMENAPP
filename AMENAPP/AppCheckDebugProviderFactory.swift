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

/// Debug provider factory for App Check - use only in DEBUG builds
class AppCheckDebugProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        // Always use debug provider when using this factory
        // For production, use DeviceCheckProviderFactory directly in AppDelegate
        return AppCheckDebugProvider(app: app)
    }
}

/// Extension to configure App Check based on build configuration
extension FirebaseApp {
    static func configureAppCheck() {
        #if DEBUG
        // For development/simulator: Use debug provider
        print("🔧 Configuring App Check with DEBUG provider (simulator compatible)")
        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        #else
        // For production: Use DeviceCheck provider
        print("🔧 Configuring App Check with DeviceCheck provider (production)")
        let providerFactory = DeviceCheckProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        #endif
    }
}
