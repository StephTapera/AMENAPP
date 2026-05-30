// AMENQuickActionManager.swift
// AMENAPP
//
// Manages iOS Home Screen quick actions (3D Touch / Haptic Touch long-press shortcuts).
//
// Architecture overview:
//
//  ┌─────────────────────────────────────────────────────────────────┐
//  │  Home Screen long-press                                          │
//  │  ↓                                                               │
//  │  UIApplicationShortcutItem (type string)                         │
//  │  ↓                                                               │
//  │  AppDelegate.application(_:performActionFor:completionHandler:)  │
//  │  ↓                                                               │
//  │  AMENQuickActionManager.handle(_:)                               │
//  │  ↓                                                               │
//  │  AppNavigationRouter.shared.navigate(to: AppDestination)         │
//  │  (router handles cold-launch queuing, auth gating, tab routing)  │
//  └─────────────────────────────────────────────────────────────────┘
//
// Cold launch path:
//   AppDelegate.didFinishLaunchingWithOptions receives the shortcut item in
//   launchOptions[.shortcutItem]. It calls AMENQuickActionManager.handle().
//   AppNavigationRouter queues the destination until sceneDidBecomeReady() +
//   authDidBecomeReady() are both called from ContentView.mainContent.
//
// Warm/foreground path:
//   AppDelegate.application(_:performActionFor:completionHandler:) fires.
//   AMENQuickActionManager calls AppNavigationRouter directly; if the scene is
//   already ready the router navigates immediately.
//
// "Require Face ID" special case:
//   This action is a SETTINGS TOGGLE, not a navigation destination. Tapping it
//   flips the app-lock preference via BiometricAuthService without navigating.

import UIKit
import FirebaseAuth

// MARK: - Quick Action Type Strings
// These string values are used as UIApplicationShortcutItem type identifiers.
// They appear in Info.plist (for static shortcuts) and in code (for dynamic ones).
// Keep them stable — changing them breaks existing shortcuts on user devices.

enum AMENQuickActionType: String, CaseIterable {
    case newPost        = "com.amen.app.quickaction.newpost"
    case messages       = "com.amen.app.quickaction.messages"
    case search         = "com.amen.app.quickaction.search"
    case activity       = "com.amen.app.quickaction.activity"
    case bereanAI       = "com.amen.app.quickaction.berean"
    case prayer         = "com.amen.app.quickaction.prayer"
    case myProfile      = "com.amen.app.quickaction.profile"
    case requireFaceID  = "com.amen.app.quickaction.requirefaceid"

    // Human-readable title shown in the long-press menu
    var title: String {
        switch self {
        case .newPost:        return "New Post"
        case .messages:       return "Messages"
        case .search:         return "Search"
        case .activity:       return "Activity"
        case .bereanAI:       return "Ask Berean"
        case .prayer:         return "Prayer"
        case .myProfile:      return "My Profile"
        case .requireFaceID:  return "Require Face ID"
        }
    }

    // SF Symbol name mapped to UIApplicationShortcutIcon.IconType
    // iOS maps these system names automatically — no custom assets needed.
    var shortcutIcon: UIApplicationShortcutIcon {
        switch self {
        case .newPost:        return UIApplicationShortcutIcon(systemImageName: "plus.circle.fill")
        case .messages:       return UIApplicationShortcutIcon(systemImageName: "bubble.left.and.bubble.right.fill")
        case .search:         return UIApplicationShortcutIcon(systemImageName: "magnifyingglass")
        case .activity:       return UIApplicationShortcutIcon(systemImageName: "bell.fill")
        case .bereanAI:       return UIApplicationShortcutIcon(systemImageName: "book.closed.fill")
        case .prayer:         return UIApplicationShortcutIcon(systemImageName: "hands.sparkles.fill")
        case .myProfile:      return UIApplicationShortcutIcon(systemImageName: "person.crop.circle.fill")
        case .requireFaceID:  return UIApplicationShortcutIcon(systemImageName: "faceid")
        }
    }
}

// MARK: - Quick Action Manager

/// Singleton that bridges UIApplicationShortcutItem events into canonical navigation
/// via AppNavigationRouter. All routing decisions (tab, sheet, cold-launch queueing,
/// auth gating) are delegated to AppNavigationRouter — this class only translates the
/// UIKit shortcut type string into an AppDestination.
@MainActor
final class AMENQuickActionManager {

    static let shared = AMENQuickActionManager()
    private init() {}

    // MARK: - Handle a shortcut item (call from AppDelegate)

    /// Convert a UIApplicationShortcutItem into an AppDestination and route it.
    ///
    /// For navigation destinations this calls `AppNavigationRouter.shared.navigate(to:)`.
    /// For the "Require Face ID" settings toggle this flips the biometric preference
    /// and does NOT navigate anywhere.
    ///
    /// Cold launch: the router queues the destination until sceneDidBecomeReady() is called.
    /// Warm launch: the router resolves immediately if the scene and auth are ready.
    func handle(_ shortcutItem: UIApplicationShortcutItem) {
        guard let actionType = AMENQuickActionType(rawValue: shortcutItem.type) else {
            dlog("⚠️ [QuickAction] Unknown shortcut type: \(shortcutItem.type)")
            return
        }
        dlog("✅ [QuickAction] Received: \(actionType.title)")

        // Special case: "Require Face ID" is a toggle, not a navigation destination.
        if actionType == .requireFaceID {
            handleRequireFaceIDToggle()
            return
        }

        // "Continue Draft" reuses the newPost type string with source="draft" in userInfo.
        let source = shortcutItem.userInfo?["source"] as? String
        let destination = destination(for: actionType, source: source)

        AppNavigationRouter.shared.navigate(to: destination)
    }

    // MARK: - Install dynamic shortcuts

    /// Rebuild the dynamic quick actions based on current app state.
    /// Call this after sign-in, after the user changes key settings,
    /// or when you want to surface contextual shortcuts (e.g. "Continue draft").
    ///
    /// iOS supports up to 4 total quick actions (static + dynamic combined).
    /// Static shortcuts defined in Info.plist always appear first. We use 0 static
    /// shortcuts (no Info.plist entries) so we have full control at runtime.
    func installShortcuts(hasDraft: Bool = false, unreadMessageCount: Int = 0) {
        guard Auth.auth().currentUser != nil else {
            // If the user is signed out, clear all shortcuts — they'd fail auth gate anyway
            UIApplication.shared.shortcutItems = []
            return
        }

        var items: [UIApplicationShortcutItem] = []

        // 1. New Post — always first, highest daily engagement action
        items.append(makeShortcut(.newPost))

        // 2. Messages or "Continue draft" — contextual slot
        if hasDraft {
            // Surface "Continue Draft" when user has a saved draft — high-value recovery
            let draft = UIApplicationShortcutItem(
                type: AMENQuickActionType.newPost.rawValue,
                localizedTitle: "Continue Draft",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "doc.text.fill"),
                userInfo: ["source": "draft" as NSSecureCoding]
            )
            items.append(draft)
        } else if unreadMessageCount > 0 {
            // Surface unread count as subtitle when messages are waiting
            let msgItem = UIApplicationShortcutItem(
                type: AMENQuickActionType.messages.rawValue,
                localizedTitle: AMENQuickActionType.messages.title,
                localizedSubtitle: "\(unreadMessageCount) unread",
                icon: AMENQuickActionType.messages.shortcutIcon,
                userInfo: nil
            )
            items.append(msgItem)
        } else {
            items.append(makeShortcut(.messages))
        }

        // 3. Activity / Notifications
        items.append(makeShortcut(.activity))

        // 4. Berean AI — differentiating, high-signal action unique to AMEN
        items.append(makeShortcut(.bereanAI))

        UIApplication.shared.shortcutItems = items
        dlog("✅ [QuickAction] Installed \(items.count) shortcuts")
    }

    /// Remove all dynamic shortcuts (e.g. on sign-out)
    func clearShortcuts() {
        UIApplication.shared.shortcutItems = []
    }

    // MARK: - Private helpers

    private func makeShortcut(_ type: AMENQuickActionType) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: type.rawValue,
            localizedTitle: type.title,
            localizedSubtitle: nil,
            icon: type.shortcutIcon,
            userInfo: nil
        )
    }

    /// Map a quick-action type (plus optional source metadata) to an AppDestination.
    private func destination(for type: AMENQuickActionType, source: String?) -> AppDestination {
        switch type {
        case .newPost:
            // "Continue Draft" reuses the newPost type with source="draft"
            return source == "draft" ? .continueDraft : .newPost
        case .messages:
            return .messages
        case .search:
            return .search()
        case .activity:
            return .activity
        case .bereanAI:
            return .askBerean()
        case .prayer:
            // Open the prayer composer directly instead of switching to the Resources tab.
            return .prayerNew
        case .myProfile:
            return .profile
        case .requireFaceID:
            // Never reached here — handled separately in handle(_:) above
            return .settings()
        }
    }

    /// Toggle the app-wide Face ID / biometric lock preference.
    /// This is a settings mutation, not a navigation action.
    private func handleRequireFaceIDToggle() {
        let service = BiometricAuthService.shared
        if service.isBiometricEnabled {
            service.disableBiometric()
            dlog("🔓 [QuickAction] Require Face ID → disabled")
        } else {
            service.enableBiometric()
            dlog("🔒 [QuickAction] Require Face ID → enabled")
        }
    }
}
