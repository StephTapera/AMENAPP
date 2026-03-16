//
//  BereanLiveActivityService.swift
//  AMENAPP
//
//  Manages the Berean AI Dynamic Island Live Activity lifecycle.
//  Starts the activity when user taps Berean on a post, streams
//  the response to the Dynamic Island, and handles dismissal.
//

import Foundation
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
class BereanLiveActivityService: ObservableObject {
    static let shared = BereanLiveActivityService()

    @Published var isActivityActive = false
    @Published var showFallbackSheet = false
    @Published var fallbackState: BereanActivityAttributes.ContentState?
    @Published var fallbackPostPreview: String = ""

    #if canImport(ActivityKit)
    private var currentActivity: Activity<BereanActivityAttributes>?
    #endif

    private init() {}

    /// Whether the device supports Live Activities (Dynamic Island).
    var supportsLiveActivities: Bool {
        #if canImport(ActivityKit)
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }

    // MARK: - Start Activity

    /// Start a Berean Live Activity for a post. Falls back to bottom sheet
    /// on devices without Dynamic Island.
    func startActivity(for post: Post) {
        let postPreview = String(post.content.prefix(60))

        guard supportsLiveActivities else {
            // Fallback: show bottom sheet instead of Dynamic Island
            fallbackPostPreview = postPreview
            fallbackState = BereanActivityAttributes.ContentState(
                phase: .loading,
                responseText: "",
                sourceCount: 0,
                scriptures: []
            )
            showFallbackSheet = true
            Task { await fetchResponse(postID: post.firebaseId ?? post.id.uuidString, postContent: post.content) }
            return
        }

        #if canImport(ActivityKit)
        let attributes = BereanActivityAttributes(
            postID: post.firebaseId ?? post.id.uuidString,
            postAuthor: post.authorUsername ?? post.authorName,
            postPreview: postPreview
        )

        let initialState = BereanActivityAttributes.ContentState(
            phase: .loading,
            responseText: "",
            sourceCount: 0,
            scriptures: []
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: Date().addingTimeInterval(120)),
                pushType: nil
            )
            currentActivity = activity
            isActivityActive = true
            HapticManager.impact(style: .medium)

            Task {
                await fetchResponse(postID: post.firebaseId ?? post.id.uuidString, postContent: post.content)
            }
        } catch {
            // Fallback to sheet
            fallbackPostPreview = postPreview
            fallbackState = initialState
            showFallbackSheet = true
            Task { await fetchResponse(postID: post.firebaseId ?? post.id.uuidString, postContent: post.content) }
        }
        #endif
    }

    // MARK: - Fetch & Stream Response

    private func fetchResponse(postID: String, postContent: String) async {
        // Update to responding phase
        await updateState(.init(
            phase: .responding,
            responseText: "Analyzing this post through a biblical lens...",
            sourceCount: 0,
            scriptures: []
        ))

        do {
            // Call Berean AI via Cloud Functions
            let result = try await CloudFunctionsService.shared.call(
                "bereanPostAssist",
                data: [
                    "postContent": postContent,
                    "postId": postID,
                    "purpose": "dynamic_island_insight",
                ] as [String: Any]
            )

            guard let dict = result as? [String: Any],
                  let text = dict["text"] as? String else {
                await updateState(.init(phase: .error, responseText: "Could not generate insight.", sourceCount: 0, scriptures: []))
                return
            }

            let scriptures = dict["scriptures"] as? [String] ?? []
            let sourceCount = dict["sourceCount"] as? Int ?? scriptures.count

            await updateState(.init(
                phase: .complete,
                responseText: text,
                sourceCount: sourceCount,
                scriptures: Array(scriptures.prefix(3))
            ))

            HapticManager.notification(type: .success)

        } catch {
            await updateState(.init(
                phase: .error,
                responseText: "Berean is unavailable right now.",
                sourceCount: 0,
                scriptures: []
            ))
        }
    }

    // MARK: - Update State

    private func updateState(_ state: BereanActivityAttributes.ContentState) async {
        // Update fallback sheet state
        fallbackState = state

        // Update Live Activity
        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }
        await activity.update(
            ActivityContent(state: state, staleDate: state.phase == .complete ? nil : Date().addingTimeInterval(120))
        )
        #endif
    }

    // MARK: - End Activity

    func endActivity() async {
        isActivityActive = false
        showFallbackSheet = false

        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }
        let finalState = BereanActivityAttributes.ContentState(
            phase: .complete,
            responseText: activity.content.state.responseText,
            sourceCount: activity.content.state.sourceCount,
            scriptures: activity.content.state.scriptures
        )
        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .immediate
        )
        currentActivity = nil
        #endif
    }

    /// End activity when app comes to foreground and user navigated away.
    func endIfStale() async {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }
        if activity.content.state.phase == .complete {
            await endActivity()
        }
        #endif
    }
}
