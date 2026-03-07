//
//  BundleConfig.swift
//  AMENAPP
//
//  Reads API keys injected into Info.plist at build time via Config.xcconfig.
//

import Foundation

enum BundleConfig {
    /// Returns a config value from Info.plist.
    ///
    /// Keys are injected at build time: Config.xcconfig → Build Settings → Info.plist.
    /// If a key is missing the xcconfig is not assigned to the active build configuration.
    static func string(forKey key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            // Use print (not assertionFailure) so Debug builds don't crash when
            // Config.local.xcconfig is not yet set up. Callers fall back to "".
            #if DEBUG
            print("⚠️ BundleConfig: key '\(key)' is missing or empty in Info.plist. " +
                  "Copy Config.xcconfig → Config.local.xcconfig and add real key values.")
            #endif
            return nil
        }
        return value
    }
}
