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
import ActivityKit

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

    /// Trigger a Berean insight for a post using Dynamic Island Live Activity.
    /// Falls back to bottom sheet if Live Activities are not available.
    func startActivity(for post: Post) {
        let postPreview = String(post.content.prefix(60))
        let postID = post.firebaseId ?? post.id.uuidString
        
        currentPostID = postID
        fallbackPostPreview = postPreview
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // Try to start Live Activity (Dynamic Island)
        let attributes = BereanActivityAttributes(
            postID: postID,
            postAuthor: post.authorName,
            postPreview: postPreview
        )
        let initialState = BereanActivityAttributes.ContentState(
            phase: .loading, responseText: "", sourceCount: 0, scriptures: []
        )
        
        do {
            let activity = try ActivityKit.Activity<BereanActivityAttributes>.request(
                attributes: attributes,
                content: ActivityKit.ActivityContent(
                    state: initialState,
                    staleDate: Date(timeIntervalSinceNow: 120)
                )
            )
            isActivityActive = true
            dlog("✨ Berean Live Activity started in Dynamic Island")
            
            // Fetch and update the activity
            Task {
                await fetchResponseForActivity(
                    postID: postID,
                    postContent: post.content,
                    activity: activity
                )
            }
        } catch {
            // Fallback to sheet if Live Activities not available
            dlog("⚠️ Live Activity unavailable, showing fallback sheet: \(error)")
            fallbackState = initialState
            showFallbackSheet = true
            isActivityActive = true
            
            Task {
                await fetchResponse(
                    postID: postID,
                    postContent: post.content
                )
            }
        }
    }

    // MARK: - Fetch Response (for Live Activity)
    
    private func fetchResponseForActivity(
        postID: String,
        postContent: String,
        activity: ActivityKit.Activity<BereanActivityAttributes>
    ) async {
        // Update to responding phase
        let respondingState = BereanActivityAttributes.ContentState(
            phase: .responding,
            responseText: "Analyzing this post through a biblical lens...",
            sourceCount: 0,
            scriptures: []
        )
        await activity.update(
            ActivityContent(state: respondingState, staleDate: Date(timeIntervalSinceNow: 120))
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
                let errorState = BereanActivityAttributes.ContentState(
                    phase: .error, responseText: "Could not generate insight.",
                    sourceCount: 0, scriptures: []
                )
                await activity.update(
                    ActivityContent(state: errorState, staleDate: Date(timeIntervalSinceNow: 30))
                )
                // Auto-dismiss after 5 seconds on error
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await activity.end(
                    ActivityContent(state: errorState, staleDate: nil),
                    dismissalPolicy: .immediate
                )
                isActivityActive = false
                return
            }
            
            let scriptures = dict["scriptures"] as? [String] ?? []
            let sourceCount = dict["sourceCount"] as? Int ?? scriptures.count
            
            let completeState = BereanActivityAttributes.ContentState(
                phase: .complete,
                responseText: String(text.prefix(200)),
                sourceCount: sourceCount,
                scriptures: Array(scriptures.prefix(3))
            )
            
            await activity.update(
                ActivityContent(state: completeState, staleDate: Date(timeIntervalSinceNow: 300))
            )
            
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            
            // Auto-dismiss after 30 seconds
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await activity.end(
                ActivityContent(state: completeState, staleDate: nil),
                dismissalPolicy: .default
            )
            isActivityActive = false
            
        } catch {
            let errorState = BereanActivityAttributes.ContentState(
                phase: .error,
                responseText: "Berean is unavailable right now.",
                sourceCount: 0,
                scriptures: []
            )
            await activity.update(
                ActivityContent(state: errorState, staleDate: Date(timeIntervalSinceNow: 30))
            )
            // Auto-dismiss after 5 seconds on error
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await activity.end(
                ActivityContent(state: errorState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            isActivityActive = false
        }
    }

    // MARK: - Fetch Response (for fallback sheet)

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
