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
//  │  AMENQuickActionManager.handle(_:) → stores pendingRoute         │
//  │  ↓                                                               │
//  │  ContentView reads pendingRoute once auth resolves               │
//  │  ↓                                                               │
//  │  Navigates to correct tab / sheet / screen                       │
//  └─────────────────────────────────────────────────────────────────┘
//
// Cold launch path:
//   AppDelegate.didFinishLaunchingWithOptions receives the shortcut item
//   in launchOptions[.shortcutItem]. It stores it via AMENQuickActionManager.
//   ContentView picks it up as soon as auth resolves.
//
// Warm/foreground path:
//   AppDelegate.application(_:performActionFor:completionHandler:) fires.
//   AMENQuickActionManager stores the route. ContentView acts immediately
//   because it's already displayed and watching pendingRoute.

import UIKit
import Combine
import FirebaseAuth

// MARK: - Quick Action Type Strings
// These string values are used as UIApplicationShortcutItem type identifiers.
// They appear in Info.plist (for static shortcuts) and in code (for dynamic ones).
// Keep them stable — changing them breaks existing shortcuts on user devices.

enum AMENQuickActionType: String, CaseIterable {
    case newPost      = "com.amen.app.quickaction.newpost"
    case messages     = "com.amen.app.quickaction.messages"
    case search       = "com.amen.app.quickaction.search"
    case activity     = "com.amen.app.quickaction.activity"
    case bereanAI     = "com.amen.app.quickaction.berean"
    case prayer       = "com.amen.app.quickaction.prayer"
    case myProfile    = "com.amen.app.quickaction.profile"

    // Human-readable title shown in the long-press menu
    var title: String {
        switch self {
        case .newPost:   return "New Post"
        case .messages:  return "Messages"
        case .search:    return "Search"
        case .activity:  return "Activity"
        case .bereanAI:  return "Ask Berean"
        case .prayer:    return "Prayer"
        case .myProfile: return "My Profile"
        }
    }

    // SF Symbol name mapped to UIApplicationShortcutIcon.IconType
    // iOS maps these system names automatically — no custom assets needed.
    var shortcutIcon: UIApplicationShortcutIcon {
        switch self {
        case .newPost:   return UIApplicationShortcutIcon(systemImageName: "plus.circle.fill")
        case .messages:  return UIApplicationShortcutIcon(systemImageName: "bubble.left.and.bubble.right.fill")
        case .search:    return UIApplicationShortcutIcon(systemImageName: "magnifyingglass")
        case .activity:  return UIApplicationShortcutIcon(systemImageName: "bell.fill")
        case .bereanAI:  return UIApplicationShortcutIcon(systemImageName: "book.closed.fill")
        case .prayer:    return UIApplicationShortcutIcon(systemImageName: "hands.sparkles.fill")
        case .myProfile: return UIApplicationShortcutIcon(systemImageName: "person.crop.circle.fill")
        }
    }
}

// MARK: - App Route
// Describes where the app should navigate after a quick action fires.
// Designed to be extended — add new cases here as the app grows.

enum AMENAppRoute: Equatable {
    case newPost                        // Open the create-post composer
    case messages                       // Switch to messages tab
    case search                         // Switch to discovery/search tab
    case activity                       // Switch to notifications tab
    case bereanAI                       // Open Berean AI assistant sheet
    case prayer                         // Switch to prayer tab (or prayer within home)
    case myProfile                      // Switch to profile tab
}

// MARK: - Quick Action Manager

/// Singleton that bridges UIApplicationShortcutItem events into SwiftUI navigation.
/// Stores a pending route when the app cannot navigate immediately (cold launch,
/// auth not yet resolved, onboarding in progress) and publishes it once ready.
@MainActor
final class AMENQuickActionManager: ObservableObject {

    static let shared = AMENQuickActionManager()
    private init() {}

    // Published so ContentView can react with .onChange(of: pendingRoute)
    @Published private(set) var pendingRoute: AMENAppRoute? = nil

    // MARK: - Handle a shortcut item (call from AppDelegate)

    /// Convert a UIApplicationShortcutItem into an AMENAppRoute and store it.
    /// ContentView will consume it once the user is authenticated and the UI is ready.
    func handle(_ shortcutItem: UIApplicationShortcutItem) {
        guard let actionType = AMENQuickActionType(rawValue: shortcutItem.type) else {
            print("⚠️ [QuickAction] Unknown shortcut type: \(shortcutItem.type)")
            return
        }
        print("✅ [QuickAction] Received: \(actionType.title)")
        pendingRoute = route(for: actionType)
    }

    /// Call this after ContentView has successfully navigated to the destination.
    /// Clears the pending route so it doesn't fire again on the next re-appear.
    func consumePendingRoute() {
        pendingRoute = nil
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
        print("✅ [QuickAction] Installed \(items.count) shortcuts")
    }

    /// Remove all dynamic shortcuts (e.g. on sign-out)
    func clearShortcuts() {
        UIApplication.shared.shortcutItems = []
        pendingRoute = nil
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

    private func route(for type: AMENQuickActionType) -> AMENAppRoute {
        switch type {
        case .newPost:   return .newPost
        case .messages:  return .messages
        case .search:    return .search
        case .activity:  return .activity
        case .bereanAI:  return .bereanAI
        case .prayer:    return .prayer
        case .myProfile: return .myProfile
        }
    }
}
