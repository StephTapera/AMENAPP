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

#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class BereanActivityManager: ObservableObject {
    static let shared = BereanActivityManager()

    @Published private(set) var isActive = false
    @Published private(set) var currentSessionID: String?

    #if canImport(ActivityKit)
    private var currentActivity: Activity<BereanActivityAttributes>?
    #endif

    private init() {}

    // MARK: - Start Session

    /// Starts a new Live Activity when the user submits a Berean question.
    func startSession(question: String) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            dlog("⚠️ BereanActivityManager: Live Activities not enabled")
            return
        }

        // End any existing session first
        if currentActivity != nil {
            Task { await endSession() }
        }

        let sessionID = UUID().uuidString
        let attributes = BereanActivityAttributes(sessionID: sessionID)
        let initialState = BereanActivityAttributes.ContentState.thinking(question: question)

        do {
            let activity = try Activity<BereanActivityAttributes>.request(
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
        #endif
    }

    // MARK: - Update: Thinking

    /// Updates the activity to show thinking state with the user's question.
    func updateThinking(question: String) {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }
        let state = BereanActivityAttributes.ContentState.thinking(question: question)
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 120))
            )
        }
        #endif
    }

    // MARK: - Update: Streaming

    /// Updates the activity as response tokens stream in.
    /// Call this periodically (e.g. every 5 words) to stay within ActivityKit update budget.
    func updateStreaming(question: String, snippet: String) {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }
        let state = BereanActivityAttributes.ContentState.responding(
            question: question,
            snippet: snippet
        )
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 120))
            )
        }
        #endif
    }

    // MARK: - Update: Complete

    /// Transitions to the complete state with final response and optional scripture.
    func updateComplete(question: String, snippet: String, scriptureRef: String?, scriptureText: String?) {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }
        let state = BereanActivityAttributes.ContentState.complete(
            question: question,
            snippet: snippet,
            ref: scriptureRef,
            refText: scriptureText
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
        #endif
    }

    // MARK: - End Session

    /// Ends the current Live Activity immediately.
    func endSession() async {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }
        let finalState = BereanActivityAttributes.ContentState(
            phase: .complete, question: "", responseSnippet: ""
        )
        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .immediate
        )
        dlog("✚ BereanActivityManager: ended session \(currentSessionID ?? "?")")
        currentActivity = nil
        #endif
        currentSessionID = nil
        isActive = false
    }
}
