//
//  BereanActivityManager.swift
//  AMENAPP
//
//  Manages the Berean AI Live Activity (ActivityKit Dynamic Island).
//  Starts a session when the user sends a question, streams updates
//  as tokens arrive, and ends the activity when complete or dismissed.
//

import Foundation
import SwiftUI
import ActivityKit
import Combine

@MainActor
final class BereanActivityManager: ObservableObject {
    static let shared = BereanActivityManager()

    @Published private(set) var isActive = false
    @Published private(set) var currentSessionID: String?

    private var currentActivity: ActivityKit.Activity<BereanActivityAttributes>?

    private init() {}

    // MARK: - Start Session

    /// Starts a new Live Activity when the user submits a Berean question.
    func startSession(question: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            dlog("⚠️ BereanActivityManager: Live Activities not enabled")
            return
        }

        // End any existing session first
        if currentActivity != nil {
            Task { await endSession() }
        }

        let sessionID = UUID().uuidString
        let attributes = BereanActivityAttributes(
            postID: sessionID,
            postAuthor: "",
            postPreview: String(question.prefix(100))
        )
        let initialState = BereanActivityAttributes.ContentState(
            phase: .loading,
            responseText: "",
            sourceCount: 0,
            scriptures: []
        )

        do {
            let activity = try ActivityKit.Activity<BereanActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(
                    state: initialState,
                    staleDate: Date(timeIntervalSinceNow: 120)
                )
            )
            currentActivity = activity
            currentSessionID = sessionID
            isActive = true
            dlog("✚ BereanActivityManager: started session \(sessionID)")
        } catch {
            dlog("⚠️ BereanActivityManager: failed to start — \(error.localizedDescription)")
        }
    }

    // MARK: - Update: Thinking

    /// Updates the activity to show thinking state with the user's question.
    func updateThinking(question: String) {
        guard let activity = currentActivity else { return }
        let state = BereanActivityAttributes.ContentState(
            phase: .loading,
            responseText: "",
            sourceCount: 0,
            scriptures: []
        )
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 120))
            )
        }
    }

    // MARK: - Update: Streaming

    /// Updates the activity as response tokens stream in.
    /// Call this periodically (e.g. every 5 words) to stay within ActivityKit update budget.
    func updateStreaming(question: String, snippet: String) {
        guard let activity = currentActivity else { return }
        let state = BereanActivityAttributes.ContentState(
            phase: .responding,
            responseText: String(snippet.prefix(200)),
            sourceCount: 0,
            scriptures: []
        )
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 120))
            )
        }
    }

    // MARK: - Update: Complete

    /// Transitions to the complete state with final response and optional scripture.
    func updateComplete(question: String, snippet: String, scriptureRef: String?, scriptureText: String?) {
        guard let activity = currentActivity else { return }
        let state = BereanActivityAttributes.ContentState(
            phase: .complete,
            responseText: String(snippet.prefix(200)),
            sourceCount: scriptureRef != nil ? 1 : 0,
            scriptures: [scriptureRef].compactMap { $0 }
        )
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 300))
            )
        }
        // Auto-dismiss after 30 seconds in complete state
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await endSession()
        }
    }

    // MARK: - End Session

    /// Ends the current Live Activity immediately.
    func endSession() async {
        guard let activity = currentActivity else { return }
        let finalState = BereanActivityAttributes.ContentState(
            phase: .complete, responseText: "", sourceCount: 0, scriptures: []
        )
        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .default
        )
        dlog("✚ BereanActivityManager: ended session \(currentSessionID ?? "?")")
        currentActivity = nil
        currentSessionID = nil
        isActive = false
    }
}
