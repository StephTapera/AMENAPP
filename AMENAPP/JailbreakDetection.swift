//
//  JailbreakDetection.swift
//  AMENAPP
//
//  Lightweight jailbreak detection without a third-party library.
//  Detects common jailbreak indicators and logs to Crashlytics.
//  Does NOT hard-block — Apple may reject apps that refuse to run on jailbroken devices.
//  Instead, we log the signal and optionally show an advisory banner.
//

import Foundation
import UIKit
import MachO
import FirebaseCrashlytics

enum JailbreakDetection {

    /// Returns true if common jailbreak indicators are present.
    /// NOT foolproof — sophisticated jailbreaks can bypass these checks.
    /// Purpose: signal to security analytics, not enforce access control.
    static var isJailbroken: Bool {
        #if targetEnvironment(simulator)
        return false  // Simulators always fail these checks
        #else
        return hasJailbreakFiles || canWriteOutsideSandbox || hasInjectedLibraries
        #endif
    }

    // MARK: - Checks

    private static var hasJailbreakFiles: Bool {
        let paths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
            "/usr/bin/ssh",
            "/private/var/stash",
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private static var canWriteOutsideSandbox: Bool {
        let testPath = "/private/jailbreak_test_\(UUID().uuidString)"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            return true  // Should not be possible on non-jailbroken device
        } catch {
            return false
        }
    }

    private static var hasInjectedLibraries: Bool {
        // Check for common Substrate/Substitute injection libraries
        let indicators = ["MobileSubstrate", "libsodium", "SubstrateLoader", "SubstrateFunctions"]
        return indicators.contains { indicator in
            let count = _dyld_image_count()
            for i in 0..<count {
                if let name = _dyld_get_image_name(i),
                   String(cString: name).contains(indicator) {
                    return true
                }
            }
            return false
        }
    }

    // MARK: - Integration

    /// Call once at app launch (e.g. in AppDelegate.didFinishLaunchingWithOptions).
    /// Logs to Crashlytics for security analytics without blocking the user.
    static func checkAndReport() {
        let jailbroken = isJailbroken
        Crashlytics.crashlytics().setCustomValue(jailbroken, forKey: "jailbroken_device")
        if jailbroken {
            dlog("⚠️ [JailbreakDetection] Jailbreak indicators detected — logged to Crashlytics")
        }
    }
}
