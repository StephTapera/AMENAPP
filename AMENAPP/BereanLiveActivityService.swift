//
//  BereanLiveActivityService.swift
//  AMENAPP
//
//  Manages the Berean AI Dynamic Island Live Activity lifecycle.
//

import Foundation
import Combine
import SwiftUI
import ActivityKit

@MainActor
class BereanLiveActivityService: ObservableObject {
    static let shared = BereanLiveActivityService()

    @Published var isActivityActive = false
    @Published var showFallbackSheet = false
    @Published var fallbackState: BereanActivityAttributes.ContentState?
    @Published var fallbackPostPreview: String = ""

    private var currentActivity: Activity<BereanActivityAttributes>?

    private init() {}

    var supportsLiveActivities: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Start Activity

    func startActivity(for post: Post) {
        let postPreview = String(post.content.prefix(60))
        let initialState = BereanActivityAttributes.ContentState(
            phase: .loading, responseText: "", sourceCount: 0, scriptures: []
        )

        guard supportsLiveActivities else {
            fallbackPostPreview = postPreview
            fallbackState = initialState
            showFallbackSheet = true
            Task { await fetchResponse(postID: post.firebaseId ?? post.id.uuidString, postContent: post.content) }
            return
        }

        let attributes = BereanActivityAttributes(
            postID: post.firebaseId ?? post.id.uuidString,
            postAuthor: post.authorUsername ?? post.authorName,
            postPreview: postPreview
        )

        do {
            let content = ActivityContent(state: initialState, staleDate: Date().addingTimeInterval(120))
            let activity = try Activity<BereanActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            currentActivity = activity
            isActivityActive = true
            HapticManager.impact(style: .medium)

            Task {
                await fetchResponse(postID: post.firebaseId ?? post.id.uuidString, postContent: post.content)
            }
        } catch {
            fallbackPostPreview = postPreview
            fallbackState = initialState
            showFallbackSheet = true
            Task { await fetchResponse(postID: post.firebaseId ?? post.id.uuidString, postContent: post.content) }
        }
    }

    // MARK: - Fetch & Stream Response

    private func fetchResponse(postID: String, postContent: String) async {
        await updateState(BereanActivityAttributes.ContentState(
            phase: .responding,
            responseText: "Analyzing this post through a biblical lens...",
            sourceCount: 0,
            scriptures: []
        ))

        do {
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
                await updateState(BereanActivityAttributes.ContentState(
                    phase: .error, responseText: "Could not generate insight.", sourceCount: 0, scriptures: []))
                return
            }

            let scriptures = dict["scriptures"] as? [String] ?? []
            let sourceCount = dict["sourceCount"] as? Int ?? scriptures.count

            await updateState(BereanActivityAttributes.ContentState(
                phase: .complete,
                responseText: text,
                sourceCount: sourceCount,
                scriptures: Array(scriptures.prefix(3))
            ))

            HapticManager.notification(type: .success)

        } catch {
            await updateState(BereanActivityAttributes.ContentState(
                phase: .error,
                responseText: "Berean is unavailable right now.",
                sourceCount: 0,
                scriptures: []
            ))
        }
    }

    // MARK: - Update State

    private func updateState(_ state: BereanActivityAttributes.ContentState) async {
        fallbackState = state

        guard let activity = currentActivity else { return }
        let staleDate: Date? = state.phase == .complete ? nil : Date().addingTimeInterval(120)
        await activity.update(ActivityContent(state: state, staleDate: staleDate))
    }

    // MARK: - End Activity

    func endActivity() async {
        isActivityActive = false
        showFallbackSheet = false

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
    }

    func endIfStale() async {
        guard let activity = currentActivity else { return }
        if activity.content.state.phase == .complete {
            await endActivity()
        }
    }
}
