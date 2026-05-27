//
//  AmenContentPreflightService.swift
//  AMENAPP
//
//  Runs preflight checks before any content is published.
//  Integrates with AmenTrustSafetyService for backend authority.
//
//  UX contract:
//    - Publish button disabled until preflight returns allow/allow_with_label
//    - Blocked: show reason, no publish
//    - Labeled: show label preview, allow publish with label
//    - Checking: disable publish, show spinner
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AmenContentPreflightService: ObservableObject {

    static let shared = AmenContentPreflightService()

    private let safety = AmenTrustSafetyService.shared
    private let flags = AmenSafetyFeatureFlags.shared

    @Published var state: ContentPreflightState = .idle
    @Published var isRunning: Bool = false

    private var debounceTask: Task<Void, Never>?
    private var debounceInterval: Duration = .milliseconds(600)

    private init() {}

    // MARK: - Debounced text preflight (live as user types)

    func preflightTextDebounced(
        _ text: String,
        surface: ContentSurface = .post,
        contentId: String? = nil
    ) {
        debounceTask?.cancel()
        guard text.count >= 10 else {
            if state != .idle { state = .idle }
            return
        }

        debounceTask = Task {
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            await runTextPreflight(text, surface: surface, contentId: contentId)
        }
    }

    // MARK: - Authoritative backend preflight (called before publish)

    func runFinalPreflight(
        text: String?,
        mediaItems: [MediaPreflightItem] = [],
        surface: ContentSurface,
        contentId: String
    ) async -> Bool {
        isRunning = true
        state = .checking

        let decision = await safety.runBackendPreflight(
            text: text,
            mediaItems: mediaItems,
            surface: surface,
            contentId: contentId
        )

        isRunning = false
        state = safety.preflightState

        return decision.canPublish
    }

    // MARK: - Private

    private func runTextPreflight(
        _ text: String,
        surface: ContentSurface,
        contentId: String?
    ) async {
        guard flags.contentPreflightEnabled, !flags.trustSafetyKillSwitch else { return }

        isRunning = true
        _ = await safety.preflightText(text, surface: surface, contentId: contentId)
        state = safety.preflightState
        isRunning = false
    }

    func reset() {
        debounceTask?.cancel()
        state = .idle
        isRunning = false
        safety.resetPreflightState()
    }
}
