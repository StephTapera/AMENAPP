//
//  BereanLiveActivityService.swift
//  AMENAPP
//
//  Manages the Berean AI response for the Dynamic Island and fallback sheet.
//  Uses a singleton-activity pattern: checks for an existing Live Activity
//  before requesting a new one, stores the activity reference on self so
//  endActivity() can actually call activity.end(), and guards against
//  concurrent duplicate launches. This prevents targetMaximumExceeded.
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

    /// Stored ActivityKit reference — the single source of truth for whether
    /// a Live Activity is currently running. nil when no activity is active.
    private var currentActivity: ActivityKit.Activity<BereanActivityAttributes>?

    /// Prevents a second tap from entering startActivity while the first is
    /// still in its synchronous setup (Activity.request / state writes).
    private var isStarting = false

    private init() {}

    // MARK: - Start

    /// Trigger a Berean insight for a post using Dynamic Island Live Activity.
    /// If an activity is already running for THIS post, does nothing.
    /// If an activity is running for a different post, ends it first.
    /// Falls back to bottom sheet if Live Activities are not supported.
    func startActivity(for post: Post) {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        let postPreview = String(post.content.prefix(60))
        let postID = post.firestoreId   // computed: firebaseId ?? id.uuidString — never empty

        // Already showing an insight for this exact post — nothing to do.
        if currentPostID == postID && isActivityActive { return }

        currentPostID = postID
        fallbackPostPreview = postPreview
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let initialState = BereanActivityAttributes.ContentState(
            phase: .loading, responseText: "", sourceCount: 0, scriptures: []
        )

        // End any stale activities (including currentActivity and any orphans
        // left by previous crashes / terminations) before requesting a new one.
        // This is the root fix for targetMaximumExceeded.
        let orphans = ActivityKit.Activity<BereanActivityAttributes>.activities
        if !orphans.isEmpty {
            Task {
                let endContent = ActivityContent(
                    state: BereanActivityAttributes.ContentState(
                        phase: .complete, responseText: "", sourceCount: 0, scriptures: []
                    ),
                    staleDate: nil
                )
                for orphan in orphans {
                    await orphan.end(endContent, dismissalPolicy: .immediate)
                }
            }
        }
        currentActivity = nil

        let attributes = BereanActivityAttributes(
            postID: postID,
            postAuthor: post.authorName,
            postPreview: postPreview
        )

        do {
            let activity = try ActivityKit.Activity<BereanActivityAttributes>.request(
                attributes: attributes,
                content: ActivityKit.ActivityContent(
                    state: initialState,
                    staleDate: Date(timeIntervalSinceNow: 120)
                )
            )
            // Store on self — endActivity() will use this reference.
            currentActivity = activity
            isActivityActive = true
            dlog("✨ Berean Live Activity started in Dynamic Island")

            Task {
                await fetchResponseForActivity(
                    postID: postID,
                    postContent: post.content,
                    activity: activity
                )
            }
        } catch {
            // Fall back to bottom sheet (older devices / user has disabled Live Activities).
            dlog("⚠️ Live Activity unavailable, showing fallback sheet: \(error.localizedDescription)")
            fallbackState = initialState
            showFallbackSheet = true
            isActivityActive = true

            Task {
                await fetchResponse(postID: postID, postContent: post.content)
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

    /// Ends the current Live Activity (if any) and resets all state.
    /// Previously this only flipped flags — it never called activity.end(),
    /// leaving ActivityKit objects alive until the system hit its limit.
    func endActivity() async {
        let endContent = ActivityContent(
            state: BereanActivityAttributes.ContentState(
                phase: .complete,
                responseText: fallbackState?.responseText ?? "",
                sourceCount: fallbackState?.sourceCount ?? 0,
                scriptures: fallbackState?.scriptures ?? []
            ),
            staleDate: nil
        )

        // End the stored reference first.
        if let activity = currentActivity {
            await activity.end(endContent, dismissalPolicy: .immediate)
            currentActivity = nil
        }

        // Belt-and-suspenders: end any orphaned activities the system still tracks.
        for orphan in ActivityKit.Activity<BereanActivityAttributes>.activities {
            await orphan.end(endContent, dismissalPolicy: .immediate)
        }

        isActivityActive = false
        showFallbackSheet = false
        currentPostID = nil
        fallbackState = nil
    }
}
