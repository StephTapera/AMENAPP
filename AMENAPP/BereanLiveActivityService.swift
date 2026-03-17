//
//  BereanLiveActivityService.swift
//  AMENAPP
//
//  Manages the Berean AI response for the Dynamic Island and fallback sheet.
//  The actual ActivityKit Live Activity is started/updated by the widget
//  extension via BereanLiveActivityWidget. This service manages the shared
//  state and Berean API calls.
//

import Foundation
import Combine
import SwiftUI
import UIKit

@MainActor
class BereanLiveActivityService: ObservableObject {
    static let shared = BereanLiveActivityService()

    @Published var isActivityActive = false
    @Published var showFallbackSheet = false
    @Published var fallbackState: BereanActivityAttributes.ContentState?
    @Published var fallbackPostPreview: String = ""
    @Published var currentPostID: String?

    private init() {}

    // MARK: - Start

    /// Trigger a Berean insight for a post. Shows fallback bottom sheet.
    /// Dynamic Island Live Activity is handled separately by the widget extension
    /// when the app pushes an activity update.
    func startActivity(for post: Post) {
        let postPreview = String(post.content.prefix(60))
        let initialState = BereanActivityAttributes.ContentState(
            phase: .loading, responseText: "", sourceCount: 0, scriptures: []
        )

        currentPostID = post.firebaseId ?? post.id.uuidString
        fallbackPostPreview = postPreview
        fallbackState = initialState
        showFallbackSheet = true
        isActivityActive = true

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            await fetchResponse(
                postID: post.firebaseId ?? post.id.uuidString,
                postContent: post.content
            )
        }
    }

    // MARK: - Fetch Response

    private func fetchResponse(postID: String, postContent: String) async {
        fallbackState = BereanActivityAttributes.ContentState(
            phase: .responding,
            responseText: "Analyzing this post through a biblical lens...",
            sourceCount: 0,
            scriptures: []
        )

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
                fallbackState = BereanActivityAttributes.ContentState(
                    phase: .error, responseText: "Could not generate insight.",
                    sourceCount: 0, scriptures: []
                )
                return
            }

            let scriptures = dict["scriptures"] as? [String] ?? []
            let sourceCount = dict["sourceCount"] as? Int ?? scriptures.count

            fallbackState = BereanActivityAttributes.ContentState(
                phase: .complete,
                responseText: text,
                sourceCount: sourceCount,
                scriptures: Array(scriptures.prefix(3))
            )

            UINotificationFeedbackGenerator().notificationOccurred(.success)

        } catch {
            fallbackState = BereanActivityAttributes.ContentState(
                phase: .error,
                responseText: "Berean is unavailable right now.",
                sourceCount: 0,
                scriptures: []
            )
        }
    }

    // MARK: - End

    func endActivity() async {
        isActivityActive = false
        showFallbackSheet = false
        currentPostID = nil
    }
}
