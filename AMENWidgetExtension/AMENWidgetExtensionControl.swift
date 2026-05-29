//
//  AMENWidgetExtensionControl.swift
//  AMENWidgetExtension
//
//  Control Center / Lock Screen / Action Button controls (iOS 18+).
//
//  Three controls are registered:
//    • AmenNewPostControl   — "New Post"    (amenGold / .yellow tint)
//    • AmenAskBereanControl — "Ask Berean"  (amenPurple / .purple tint)
//    • AmenMessagesControl  — "Messages"    (amenBlue / .blue tint)
//
//  Widget-extension → main-app communication
//  ─────────────────────────────────────────
//  Widget extensions run in a separate process and cannot import the main app
//  module, so AppNavigationRouter is not available here. The intents write a
//  "pendingControlAction" string to the shared App Group UserDefaults
//  (group.com.amenapp.shared). AMENAPPApp reads that key whenever the scene
//  becomes .active and calls AppNavigationRouter.shared.navigate(to:) to
//  complete the routing. Setting openAppWhenRun = true ensures the main app
//  process is brought to the foreground before the key is consumed.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Shared constant

private let amenAppGroup = "group.com.amenapp.shared"
private let pendingControlActionKey = "pendingControlAction"

// MARK: - New Post Intent

/// Fires when the user taps the "New Post" control.
/// Writes "newPost" to the shared App Group so AMENAPPApp can route on foreground.
struct OpenNewPostAppIntent: AppIntent {
    static var title: LocalizedStringResource = "New Post"
    static var description = IntentDescription("Open the post composer in AMEN")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: amenAppGroup)?
            .set("newPost", forKey: pendingControlActionKey)
        return .result()
    }
}

// MARK: - Ask Berean Intent (extension-local copy)

/// Extension-local intent for the Ask Berean control.
/// Cannot reuse OpenBereanIntent from the main target (separate process).
struct ControlOpenBereanAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Berean"
    static var description = IntentDescription("Open the Berean AI assistant in AMEN")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: amenAppGroup)?
            .set("askBerean", forKey: pendingControlActionKey)
        return .result()
    }
}

// MARK: - Messages Intent

/// Fires when the user taps the "Messages" control.
/// Writes "messages" to the shared App Group so AMENAPPApp can route on foreground.
struct OpenMessagesAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Messages"
    static var description = IntentDescription("Open Messages in AMEN")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: amenAppGroup)?
            .set("messages", forKey: pendingControlActionKey)
        return .result()
    }
}

// MARK: - New Post Control

/// Control Center / Lock Screen / Action Button control for creating a new post.
/// Brand tint: amenGold (#D4A847) approximated with .yellow.
@available(iOS 18.0, *)
struct AmenNewPostControl: ControlWidget {
    static let kind: String = "com.amenapp.control.newpost"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenNewPostAppIntent()) {
                Label("New Post", systemImage: "plus.circle.fill")
                    .tint(.yellow)
            }
        }
        .displayName("New Post")
        .description("Open the AMEN post composer instantly.")
    }
}

// MARK: - Ask Berean Control

/// Control Center / Lock Screen / Action Button control for Berean AI.
/// Brand tint: amenPurple approximated with .purple.
@available(iOS 18.0, *)
struct AmenAskBereanControl: ControlWidget {
    static let kind: String = "com.amenapp.control.berean"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ControlOpenBereanAppIntent()) {
                Label("Ask Berean", systemImage: "book.closed.fill")
                    .tint(.purple)
            }
        }
        .displayName("Ask Berean")
        .description("Open the Berean AI scripture assistant instantly.")
    }
}

// MARK: - Messages Control

/// Control Center / Lock Screen / Action Button control for Messages.
/// Brand tint: amenBlue approximated with .blue.
@available(iOS 18.0, *)
struct AmenMessagesControl: ControlWidget {
    static let kind: String = "com.amenapp.control.messages"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenMessagesAppIntent()) {
                Label("Messages", systemImage: "bubble.left.and.bubble.right.fill")
                    .tint(.blue)
            }
        }
        .displayName("Messages")
        .description("Jump straight to your AMEN conversations.")
    }
}
