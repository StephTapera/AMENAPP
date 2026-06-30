import Foundation

/// Frozen flag registry for the Safe Interactive Comments lane (Path C).
///
/// DOCTRINE: every surface defaults OFF and fail-closed. Missing or malformed
/// configuration resolves OFF. No network/provider work occurs while OFF.
///
/// This is a DEDICATED registry (not `AMENFeatureFlags`) on purpose: that file is
/// hot and concurrently edited, and the repo-proven collision-safe pattern is a
/// per-subsystem flag file (cf. `SelahContextualFlags`). Production Remote Config
/// wiring is deferred to a single lane owner; until then every surface resolves
/// OFF in release builds, so the lane is a guaranteed zero behavioral diff.
enum AMENSafeInteractiveCommentsFlags {

    /// Master kill switch. OFF => the entire lane is inert.
    static var masterEnabled: Bool { resolve(Key.master) }

    // Group gates — each implies the master gate (fail-closed composition).
    static var composeModesEnabled: Bool { masterEnabled && resolve(Key.composeModes) }
    static var mediaProvidersEnabled: Bool { masterEnabled && resolve(Key.mediaProviders) }
    static var interactionsEnabled: Bool { masterEnabled && resolve(Key.interactions) }
    static var threadDynamicsEnabled: Bool { masterEnabled && resolve(Key.threadDynamics) }

    enum Key {
        static let master = "amen_safe_interactive_comments_master"
        static let composeModes = "amen_safe_interactive_comments_compose_modes"
        static let mediaProviders = "amen_safe_interactive_comments_media_providers"
        static let interactions = "amen_safe_interactive_comments_interactions"
        static let threadDynamics = "amen_safe_interactive_comments_thread_dynamics"
    }

    /// Fail-closed resolver. In release every key resolves OFF until the production
    /// Remote Config bridge is wired by the lane owner. In DEBUG a developer may opt
    /// a single surface in via UserDefaults (dev-only), which makes the ON path
    /// testable without ever shipping it enabled.
    static func resolve(_ key: String) -> Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "dev." + key)
        #else
        return false
        #endif
    }
}
