//
//  BereanLiveActivityService.swift
//  AMENAPP
//
//  Manages the Berean AI response for the Dynamic Island and fallback sheet.
//  Uses a singleton-activity pattern so post-card initiated Berean routing has
//  a single canonical implementation.
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

    private var currentActivity: ActivityKit.Activity<BereanActivityAttributes>?
    private var isStarting = false

    private init() {}

    func startActivity(for post: Post) {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        let context = BereanPostContext(post: post)
        let initialState = makeState(for: context, phase: .loading, responseText: "", sourceCount: 0, scriptures: [])

        dlog("📍 [BereanLiveActivity] PostCard tap for post \(context.postId)")
        CrashlyticsIntegration.logAction("berean_live_activity_postcard_tap")
        CrashlyticsIntegration.setAppState(key: "berean_live_activity_post_id", value: context.postId)

        if currentPostID == context.postId && isActivityActive { return }

        currentPostID = context.postId
        fallbackPostPreview = context.previewText
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let orphans = ActivityKit.Activity<BereanActivityAttributes>.activities
        if !orphans.isEmpty {
            let endContent = ActivityContent(
                state: makeState(for: context, phase: .complete, responseText: "", sourceCount: 0, scriptures: []),
                staleDate: nil
            )
            Task {
                for orphan in orphans {
                    await orphan.end(endContent, dismissalPolicy: .immediate)
                }
            }
        }
        currentActivity = nil

        let attributes = BereanActivityAttributes(
            postID: context.postId,
            postAuthor: context.authorName,
            postPreview: context.previewText
        )

        do {
            let activity = try ActivityKit.Activity<BereanActivityAttributes>.request(
                attributes: attributes,
                content: ActivityKit.ActivityContent(
                    state: initialState,
                    staleDate: Date(timeIntervalSinceNow: 120)
                )
            )
            currentActivity = activity
            isActivityActive = true
            dlog("✨ [BereanLiveActivity] Activity request succeeded for post \(context.postId)")
            CrashlyticsIntegration.logAction("berean_live_activity_request_success")

            Task {
                await fetchResponseForActivity(
                    context: context,
                    postContent: sanitizedPostContent(for: post, context: context),
                    activity: activity
                )
            }
        } catch {
            dlog("⚠️ [BereanLiveActivity] Activity request failed for post \(context.postId): \(error.localizedDescription)")
            CrashlyticsIntegration.logAction("berean_live_activity_request_failed")
            CrashlyticsIntegration.logNetworkError(error, endpoint: "activitykit_request_berean")
            fallbackState = initialState
            showFallbackSheet = true
            isActivityActive = true

            Task {
                await fetchResponse(
                    context: context,
                    postContent: sanitizedPostContent(for: post, context: context)
                )
            }
        }
    }

    private func fetchResponseForActivity(
        context: BereanPostContext,
        postContent: String,
        activity: ActivityKit.Activity<BereanActivityAttributes>
    ) async {
        let respondingState = makeState(
            for: context,
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
                    "postId": context.postId,
                    "purpose": "dynamic_island_insight",
                ] as [String: Any]
            )

            guard let dict = result as? [String: Any],
                  let text = dict["text"] as? String else {
                let errorState = makeState(
                    for: context,
                    phase: .error,
                    responseText: "Could not generate insight.",
                    sourceCount: 0,
                    scriptures: []
                )
                await activity.update(
                    ActivityContent(state: errorState, staleDate: Date(timeIntervalSinceNow: 30))
                )
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await activity.end(
                    ActivityContent(state: errorState, staleDate: nil),
                    dismissalPolicy: .immediate
                )
                isActivityActive = false
                dlog("❌ [BereanLiveActivity] Response payload invalid for post \(context.postId)")
                CrashlyticsIntegration.logAction("berean_live_activity_invalid_payload")
                return
            }

            let scriptures = dict["scriptures"] as? [String] ?? []
            let sourceCount = dict["sourceCount"] as? Int ?? scriptures.count
            let completeState = makeState(
                for: context,
                phase: .complete,
                responseText: String(text.prefix(200)),
                sourceCount: sourceCount,
                scriptures: Array(scriptures.prefix(3))
            )

            await activity.update(
                ActivityContent(state: completeState, staleDate: Date(timeIntervalSinceNow: 300))
            )

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dlog("✅ [BereanLiveActivity] Response ready for post \(context.postId)")
            CrashlyticsIntegration.logAction("berean_live_activity_response_ready")

            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await activity.end(
                ActivityContent(state: completeState, staleDate: nil),
                dismissalPolicy: .default
            )
            isActivityActive = false
        } catch {
            let errorState = makeState(
                for: context,
                phase: .error,
                responseText: "Berean is unavailable right now.",
                sourceCount: 0,
                scriptures: []
            )
            await activity.update(
                ActivityContent(state: errorState, staleDate: Date(timeIntervalSinceNow: 30))
            )
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await activity.end(
                ActivityContent(state: errorState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            isActivityActive = false
            dlog("❌ [BereanLiveActivity] Response failed for post \(context.postId): \(error.localizedDescription)")
            CrashlyticsIntegration.logNetworkError(error, endpoint: "bereanPostAssist_live_activity")
        }
    }

    private func fetchResponse(context: BereanPostContext, postContent: String) async {
        fallbackState = makeState(
            for: context,
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
                    "postId": context.postId,
                    "purpose": "dynamic_island_insight",
                ] as [String: Any]
            )

            guard let dict = result as? [String: Any],
                  let text = dict["text"] as? String else {
                fallbackState = makeState(
                    for: context,
                    phase: .error,
                    responseText: "Could not generate insight.",
                    sourceCount: 0,
                    scriptures: []
                )
                dlog("❌ [BereanLiveActivity] Fallback payload invalid for post \(context.postId)")
                return
            }

            let scriptures = dict["scriptures"] as? [String] ?? []
            let sourceCount = dict["sourceCount"] as? Int ?? scriptures.count

            fallbackState = makeState(
                for: context,
                phase: .complete,
                responseText: text,
                sourceCount: sourceCount,
                scriptures: Array(scriptures.prefix(3))
            )

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dlog("✅ [BereanLiveActivity] Fallback response ready for post \(context.postId)")
            CrashlyticsIntegration.logAction("berean_live_activity_fallback_ready")
        } catch {
            fallbackState = makeState(
                for: context,
                phase: .error,
                responseText: "Berean is unavailable right now.",
                sourceCount: 0,
                scriptures: []
            )
            dlog("❌ [BereanLiveActivity] Fallback response failed for post \(context.postId): \(error.localizedDescription)")
            CrashlyticsIntegration.logNetworkError(error, endpoint: "bereanPostAssist_fallback")
        }
    }

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

        if let activity = currentActivity {
            await activity.end(endContent, dismissalPolicy: .immediate)
            currentActivity = nil
        }

        for orphan in ActivityKit.Activity<BereanActivityAttributes>.activities {
            await orphan.end(endContent, dismissalPolicy: .immediate)
        }

        isActivityActive = false
        showFallbackSheet = false
        currentPostID = nil
        fallbackState = nil
    }

    private func makeState(
        for context: BereanPostContext,
        phase: BereanPhase,
        responseText: String,
        sourceCount: Int,
        scriptures: [String]
    ) -> BereanActivityAttributes.ContentState {
        BereanActivityAttributes.ContentState(
            phase: phase,
            responseText: responseText,
            sourceCount: sourceCount,
            scriptures: scriptures
        )
    }

    private func sanitizedPostContent(for post: Post, context: BereanPostContext) -> String {
        let collapsed = post.content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if context.isSensitive {
            dlog("🔒 [BereanLiveActivity] Using safe preview only for sensitive post \(context.postId)")
            return String(collapsed.prefix(180))
        }

        return String(collapsed.prefix(600))
    }
}
