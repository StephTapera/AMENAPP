// AppNavigationRouter.swift
// AMENAPP
//
// Single canonical router that ALL navigation surfaces funnel through.
//
// Architecture
// ────────────
//  External surfaces (Siri, Spotlight, URL schemes, quick actions, widgets)
//     │
//     ▼
//  AppDestination (canonical enum — AppDestination.swift)
//     │
//     ▼
//  AppNavigationRouter.shared.navigate(to:)
//     │
//     ├─ cold launch? → pendingDestination (released by sceneDidBecomeReady)
//     ├─ auth required but not authenticated? → holdDestination (released by authDidBecomeReady)
//     └─ ready → resolve(_:) → @Published selectedTab / pendingPresentation
//
// Wiring (ContentView mainContent):
//   1. .task   → AppNavigationRouter.shared.sceneDidBecomeReady()
//   2. @ObservedObject router.selectedTab  → viewModel.selectedTab
//   3. .onChange(router.pendingPresentation) → open sheets
//
// Do NOT add navigation logic to individual screens. This is the single source of truth.

import SwiftUI
import Foundation
import FirebaseAuth

// MARK: - AppNavigationRouter

@MainActor
final class AppNavigationRouter: ObservableObject {

    // MARK: - Singleton

    static let shared = AppNavigationRouter()
    private init() {}

    // MARK: - Published state (root scene observes these)

    /// Drives the TabView selection. Bind this to `viewModel.selectedTab`.
    @Published private(set) var selectedTab: Int = 0

    /// Set when a destination requires presenting a sheet/modal (e.g. Berean, composer).
    /// Root ContentView should observe this and present the appropriate sheet,
    /// then clear it by calling `clearPendingPresentation()`.
    @Published private(set) var pendingPresentation: AppDestination? = nil

    // MARK: - Lifecycle gates

    /// True once the root navigation tree is mounted and sceneDidBecomeReady() has been called.
    private var sceneIsReady = false

    /// True once the user is authenticated and all auth guards have been passed.
    private var authIsReady = false

    /// Destination queued during cold launch (before sceneIsReady).
    private var coldLaunchDestination: AppDestination? = nil

    /// Destination queued because auth is not yet resolved.
    private var authPendingDestination: AppDestination? = nil

    /// Timeout task that fires if auth never resolves within 10 seconds.
    private var authTimeoutTask: Task<Void, Never>? = nil

    // MARK: - Injected closures (set by ContentView / root scene)

    /// Returns true when the user is authenticated.
    var isAuthenticated: () -> Bool = {
        Auth.auth().currentUser != nil
    }

    /// Returns true when the app policy blocks this destination (e.g. Shabbat gate).
    var isDestinationBlocked: (AppDestination) -> Bool = { _ in false }

    // MARK: - Primary entry point

    /// Navigate to a canonical destination. Call this from any external surface.
    func navigate(to destination: AppDestination) {
        dlog("[AppNavigationRouter] navigate(to: \(destination.analyticsLabel))")

        // Cold-launch: scene not yet mounted — queue until sceneDidBecomeReady
        guard sceneIsReady else {
            dlog("[AppNavigationRouter] ⏸ Scene not ready — queuing cold-launch destination")
            coldLaunchDestination = destination
            return
        }

        resolve(destination)
    }

    /// Convenience overload — parse a URL and navigate.
    func navigate(to url: URL) {
        guard let destination = AppDestination(url: url) else {
            dlog("[AppNavigationRouter] ⚠️ URL not parseable as AppDestination: \(url)")
            return
        }
        navigate(to: destination)
    }

    /// Convenience overload — parse a URL string and navigate.
    func navigate(to urlString: String) {
        guard let url = URL(string: urlString) else { return }
        navigate(to: url)
    }

    // MARK: - Lifecycle signals

    /// Call once from `mainContent.onAppear` after auth resolves and tab bar is mounted.
    /// Releases any destination queued during cold launch.
    func sceneDidBecomeReady() {
        guard !sceneIsReady else { return }
        sceneIsReady = true
        dlog("[AppNavigationRouter] ✅ Scene is ready")

        if let pending = coldLaunchDestination {
            coldLaunchDestination = nil
            resolve(pending)
        }
    }

    /// Call when the user becomes authenticated.
    /// Releases any destination queued because auth was not yet ready.
    func authDidBecomeReady() {
        guard !authIsReady else { return }
        authIsReady = true
        // Cancel the timeout — auth resolved normally before the 10-second deadline.
        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        dlog("[AppNavigationRouter] ✅ Auth is ready")

        if let pending = authPendingDestination {
            authPendingDestination = nil
            resolve(pending)
        }
    }

    /// Reset the auth-ready gate (call on sign-out so the next sign-in re-arms gating).
    func authDidSignOut() {
        authIsReady = false
        authPendingDestination = nil
        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        dlog("[AppNavigationRouter] 🔓 Auth gate reset (sign-out)")
    }

    // MARK: - Presentation lifecycle

    /// Call after the sheet/modal for `pendingPresentation` has been presented.
    func clearPendingPresentation() {
        pendingPresentation = nil
    }

    // MARK: - Private resolution

    private func resolve(_ destination: AppDestination) {
        // Auth gate: hold auth-required destinations until the user is signed in
        if destination.requiresAuth && !isAuthenticated() {
            dlog("[AppNavigationRouter] ⏸ Auth required — queuing until sign-in: \(destination.analyticsLabel)")
            authPendingDestination = destination
            // Arm a 10-second timeout so the held destination doesn't block forever
            // if the auth state listener never fires (e.g. cold start with no network).
            if authTimeoutTask == nil {
                authTimeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(10))
                    } catch {
                        return  // cancelled — auth resolved normally
                    }
                    guard let self else { return }
                    await MainActor.run {
                        guard !self.authIsReady else { return }
                        dlog("[AppNavigationRouter] ⏱ Auth timeout — dropping held destination, routing to sign-in")
                        self.authPendingDestination = nil
                        self.authTimeoutTask = nil
                        // Signal the root scene to show sign-in by resetting to tab 0.
                        // ContentView observes authIsReady == false to present the auth flow.
                        self.selectedTab = 0
                        NotificationCenter.default.post(name: .amenAuthTimeout, object: nil)
                    }
                }
            }
            return
        }

        // Shabbat / app-lock gate
        if isDestinationBlocked(destination) {
            dlog("[AppNavigationRouter] 🚫 Destination blocked: \(destination.analyticsLabel)")
            selectedTab = 3
            NotificationCenter.default.post(
                name: .shabbatDeepLinkBlocked,
                object: nil,
                userInfo: ["blockedRoute": destination.analyticsLabel]
            )
            return
        }

        dlog("[AppNavigationRouter] ▶️ Resolving → \(destination.analyticsLabel)")

        switch destination {

        // ── Pure tab switches ──────────────────────────────────────────────
        case .home:
            selectedTab = 0

        case .discovery:
            selectedTab = 1

        case .messages:
            selectedTab = 2

        case .resources:
            selectedTab = 3

        case .activity:
            selectedTab = 4

        case .profile:
            selectedTab = 5

        case .gatherings:
            selectedTab = 6

        case .spaces:
            selectedTab = 7

        case .communityNotes:
            selectedTab = 8

        case .settings:
            selectedTab = 5
            if case .settings(let section) = destination, let section {
                NotificationCenter.default.post(
                    name: .navigateToSettings,
                    object: nil,
                    userInfo: ["section": section]
                )
            }

        case .search(let query):
            selectedTab = 1
            if let q = query, !q.isEmpty {
                NotificationCenter.default.post(
                    name: .amenOpenSearch,
                    object: nil,
                    userInfo: ["query": q]
                )
            }

        // ── Composer sheets ────────────────────────────────────────────────
        case .newPost:
            selectedTab = 0
            pendingPresentation = .newPost

        case .continueDraft:
            selectedTab = 0
            pendingPresentation = .continueDraft

        case .testimony:
            selectedTab = 0
            pendingPresentation = .testimony

        case .prayerNew:
            selectedTab = 3
            pendingPresentation = .prayerNew

        // ── Berean ─────────────────────────────────────────────────────────
        case .askBerean, .bereanWithVerse, .bereanWithSession:
            pendingPresentation = destination

        // ── Faith feature tabs ─────────────────────────────────────────────
        case .findChurch, .churchNotes, .reflection,
             .prayer, .churchNote:
            selectedTab = 3
            pendingPresentation = destination

        case .verseOfDay:
            selectedTab = 0
            pendingPresentation = .verseOfDay

        // ── Content detail ─────────────────────────────────────────────────
        case .post(let id, let commentId):
            selectedTab = 0
            NotificationCenter.default.post(
                name: .openPostFromNotification,
                object: nil,
                userInfo: [
                    "postId": id,
                    "scrollToCommentId": commentId as Any
                ]
            )

        case .userProfile(let userId):
            selectedTab = 5
            NotificationCenter.default.post(
                name: .openProfileFromNotification,
                object: nil,
                userInfo: ["userId": userId]
            )

        case .church:
            selectedTab = 3
            pendingPresentation = destination

        case .conversation(let id, _):
            selectedTab = 2
            BadgeCountManager.shared.clearMessages()
            NotificationCenter.default.post(
                name: .openConversation,
                object: nil,
                userInfo: ["conversationId": id]
            )

        case .groupJoinLink(let token):
            selectedTab = 2
            NotificationCenter.default.post(
                name: .openGroupJoinLink,
                object: nil,
                userInfo: ["token": token]
            )
        }
    }

}

// MARK: - Notification.Name additions

extension Notification.Name {
    /// Posted by AppNavigationRouter when a search destination is resolved with a query.
    static let amenOpenSearch = Notification.Name("amenOpenSearch")
    /// Posted when the auth-ready gate times out after 10 seconds without resolving.
    /// Observers (e.g. ContentView) should route the user to the sign-in screen.
    static let amenAuthTimeout = Notification.Name("amenAuthTimeout")
}
