// AmenIntentRouter.swift
// AMENAPP
//
// Routes intent notifications and Spotlight deep links to the correct
// in-app screen by posting a deep-link URL notification that the root
// coordinator (AMENAPPApp / ContentView) listens for.
//
// WIRING REQUIRED in AMENAPPApp.swift:
// Observe Notification.Name("amenDeepLink") and navigate based on the URL string
// delivered in userInfo["url"].

import Foundation

// MARK: - Deep Link Scheme

private enum AmenDeepLink {
    static let prayer         = "amen://prayer"
    static let berean         = "amen://berean"
    static let findChurch     = "amen://find-church"
    static let churchNotes    = "amen://church-notes"
    static let reflection     = "amen://reflection"
    static let prayerComposer = "amen://prayer-composer"
}

// MARK: - Intent Router

/// Translates Siri-intent and Spotlight notifications into AMEN deep-link URLs.
/// All methods are nonisolated so they can be called from both MainActor and
/// background contexts; URL posting is always dispatched to the main queue.
@MainActor
final class AmenIntentRouter {

    private init() {}

    // MARK: - Notification → Deep Link

    /// Call once in the app root to begin routing all AMEN intent notifications.
    /// Example (AMENAPPApp.body):
    /// ```swift
    /// .onReceive(NotificationCenter.default.publisher(for: Notification.Name("openPrayerMode"))) {
    ///     AmenIntentRouter.handle(notification: $0)
    /// }
    /// ```
    static func handle(notification: Notification) {
        let url: String?
        switch notification.name {
        case Notification.Name("openPrayerMode"):
            url = AmenDeepLink.prayer
        case Notification.Name("openBerean"):
            url = AmenDeepLink.berean
        case Notification.Name("openFindChurch"):
            url = AmenDeepLink.findChurch
        case Notification.Name("openChurchNotes"):
            url = AmenDeepLink.churchNotes
        case Notification.Name("openReflection"):
            url = AmenDeepLink.reflection
        case Notification.Name("openPrayerComposer"):
            url = AmenDeepLink.prayerComposer
        default:
            dlog("[AmenIntentRouter] Unhandled notification: \(notification.name.rawValue)")
            url = nil
        }

        guard let deepLink = url else { return }
        dlog("[AmenIntentRouter] Routing notification \(notification.name.rawValue) → \(deepLink)")
        postDeepLink(deepLink)
    }

    // MARK: - Spotlight → Deep Link

    /// Routes a Spotlight result (type + id) to the correct in-app screen.
    /// Call from the AmenSpotlightService.handleSpotlightResult(_:) result handler.
    static func routeSpotlight(type: String, id: String) {
        let url: String
        switch type {
        case AmenSpotlightService.domainPrayer:
            url = "\(AmenDeepLink.prayer)?id=\(id)"
        case AmenSpotlightService.domainChurchNote:
            url = "\(AmenDeepLink.churchNotes)?id=\(id)"
        case AmenSpotlightService.domainBerean:
            url = "\(AmenDeepLink.berean)?session=\(id)"
        case AmenSpotlightService.domainVerse:
            // Verses don't have a detail view; open Berean with the reference pre-loaded.
            url = "\(AmenDeepLink.berean)?verse=\(id)"
        default:
            dlog("[AmenIntentRouter] Unknown Spotlight type: \(type)")
            return
        }
        dlog("[AmenIntentRouter] Routing Spotlight type=\(type) id=\(id) → \(url)")
        postDeepLink(url)
    }

    // MARK: - Pending Parameter Accessors

    /// Returns the Berean question stored by AskBereanIntent and clears the stored value.
    /// Call this once after navigating to the Berean screen.
    static func pendingBereanQuestion() -> String? {
        let key = "pendingBereanQuestion"
        let value = UserDefaults.standard.string(forKey: key)
        if value != nil {
            UserDefaults.standard.removeObject(forKey: key)
            dlog("[AmenIntentRouter] Consumed pendingBereanQuestion")
        }
        return value
    }

    /// Returns the prayer message stored by SendPrayerRequestIntent and clears the stored value.
    /// Call this once after navigating to the prayer composer.
    static func pendingPrayerMessage() -> String? {
        let key = "pendingPrayerMessage"
        let value = UserDefaults.standard.string(forKey: key)
        if value != nil {
            UserDefaults.standard.removeObject(forKey: key)
            dlog("[AmenIntentRouter] Consumed pendingPrayerMessage")
        }
        return value
    }

    // MARK: - Private

    /// Broadcasts a deep-link URL string via NotificationCenter so the app root can react.
    /// The notification name "amenDeepLink" with userInfo key "url" is the contract.
    private static func postDeepLink(_ urlString: String) {
        NotificationCenter.default.post(
            name: Notification.Name("amenDeepLink"),
            object: nil,
            userInfo: ["url": urlString]
        )
    }
}
