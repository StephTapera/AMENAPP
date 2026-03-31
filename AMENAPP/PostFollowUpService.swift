//
//  PostFollowUpService.swift
//  AMENAPP
//
//  After-publish AI follow-up intelligence system for AMEN.
//  Schedules and surfaces helpful author-only actions days after posting —
//  no vanity metrics, no public engagement counts.
//
//  Design system: white background, black text (AmenColorScheme)
//  Dependencies: Foundation + Combine only. Network stubs marked with TODO comments.
//

import Foundation
import Combine

// MARK: - PostFollowUp

/// A single scheduled follow-up suggestion for a post's author.
/// Follow-ups are private to the author — never shown to other users.
struct PostFollowUp: Identifiable {
    let id: String
    let postId: String
    /// Seconds after publish when this follow-up should surface to the author.
    let triggerAfter: TimeInterval
    let type: FollowUpType
    /// The suggestion copy shown to the author in the notification / card.
    let suggestion: String
    /// Short label for the primary action button.
    let actionLabel: String
    /// Internal action identifier used to route the tap to the correct screen.
    let deepLinkAction: String
    /// `true` once the author dismisses without acting.
    var isDismissed: Bool
    /// `true` once the author completes the suggested action.
    var isCompleted: Bool

    // MARK: Follow-Up Types

    enum FollowUpType: String, Codable {
        /// Prompt to turn a reflective post into a saved Church Note.
        case turnIntoNote
        /// Prompt to extract bullet-point notes from a sermon clip.
        case sermonClipNotes
        /// Private summary of reply themes — author-only insight, never shown in feed.
        case summarizeComments
        /// Suggest a follow-up post continuing the thread.
        case suggestFollowUpPost
        /// Alert author if comment section is showing signs of tension.
        case detectRisingTension
        /// Suggest attaching or linking a related resource.
        case suggestResource
        /// Prompt to archive this post as a personal or community memory.
        case saveAsMemory
        /// Suggest reposting to a relevant Space.
        case repostToSpace
        /// Gentle wellness check — surfaced only when tension or sad language detected.
        case wellnessCheck
    }
}

// MARK: - FollowUpSchedule (internal)

/// Internal schedule definition for a post intent type.
private struct FollowUpSchedule {
    let triggerAfter: TimeInterval
    let type: PostFollowUp.FollowUpType
    let suggestion: String
    let actionLabel: String
    let deepLinkAction: String
}

// MARK: - PostFollowUpService

/// Schedules and manages after-publish intelligence follow-ups for post authors.
///
/// All follow-ups are:
/// - Private to the post author
/// - Non-vanity (no like/comment counts)
/// - Dismissible and completable
/// - Delivered through AMEN's internal notification layer
///
/// Usage:
/// ```swift
/// // After publish
/// await service.scheduleFollowUps(for: postId, intent: .testimony, mediaTypes: ["video"])
///
/// // In author's notification center / home feed card
/// await service.fetchPendingFollowUps(for: userId)
/// ```
@MainActor
final class PostFollowUpService: ObservableObject {

    // MARK: Published State

    @Published private(set) var pendingFollowUps: [PostFollowUp] = []

    // MARK: - Schedule Definitions

    /// Returns the follow-up schedule for a given post intent and media types.
    /// Each entry in the returned array will produce a `PostFollowUp` record.
    private func schedules(
        for intent: PostIntent,
        mediaTypes: [String]
    ) -> [FollowUpSchedule] {

        let hour: TimeInterval  = 3600
        let day: TimeInterval   = 86_400

        switch intent {

        // ── Testimony ──────────────────────────────────────────────────────
        case .testimony:
            return [
                FollowUpSchedule(
                    triggerAfter: 24 * hour,
                    type: .turnIntoNote,
                    suggestion: "Turn this testimony into a Church Note so your community can read it again.",
                    actionLabel: "Turn into Note",
                    deepLinkAction: "amen://notes/create-from-post"
                ),
                FollowUpSchedule(
                    triggerAfter: 7 * day,
                    type: .suggestFollowUpPost,
                    suggestion: "A week has passed — share what God has done since you posted this testimony.",
                    actionLabel: "Share Update",
                    deepLinkAction: "amen://compose?context=testimony_followup"
                ),
                FollowUpSchedule(
                    triggerAfter: 7 * day,
                    type: .saveAsMemory,
                    suggestion: "Save this testimony as a personal memory to look back on.",
                    actionLabel: "Save as Memory",
                    deepLinkAction: "amen://memories/save"
                )
            ]

        // ── Sermon Clip ────────────────────────────────────────────────────
        case .sermonClip:
            return [
                FollowUpSchedule(
                    triggerAfter: 1 * hour,
                    type: .sermonClipNotes,
                    suggestion: "Extract the key points from this sermon clip to share alongside the video.",
                    actionLabel: "Extract Key Points",
                    deepLinkAction: "amen://ai/sermon-notes?postId={{postId}}"
                ),
                FollowUpSchedule(
                    triggerAfter: 24 * hour,
                    type: .suggestFollowUpPost,
                    suggestion: "Create a reflection prompt for your community based on this message.",
                    actionLabel: "Create Reflection",
                    deepLinkAction: "amen://compose?context=sermon_reflection&postId={{postId}}"
                ),
                FollowUpSchedule(
                    triggerAfter: 3 * day,
                    type: .suggestResource,
                    suggestion: "Attach a study guide or reading plan to help people go deeper with this message.",
                    actionLabel: "Attach Resource",
                    deepLinkAction: "amen://resources/attach?postId={{postId}}"
                )
            ]

        // ── Prayer Request ─────────────────────────────────────────────────
        case .prayerRequest:
            return [
                FollowUpSchedule(
                    triggerAfter: 3 * day,
                    type: .suggestFollowUpPost,
                    suggestion: "Your community has been praying with you. Share an update on your prayer request.",
                    actionLabel: "Post Update",
                    deepLinkAction: "amen://compose?context=prayer_update"
                ),
                FollowUpSchedule(
                    triggerAfter: 7 * day,
                    type: .saveAsMemory,
                    suggestion: "Archive this prayer request so you can look back and see how God answered.",
                    actionLabel: "Save as Memory",
                    deepLinkAction: "amen://memories/save"
                )
            ]

        // ── Question ───────────────────────────────────────────────────────
        case .question:
            return [
                FollowUpSchedule(
                    triggerAfter: 4 * hour,
                    type: .summarizeComments,
                    suggestion: "Privately summarize the main themes from replies to your question.",
                    actionLabel: "Summarize Replies",
                    deepLinkAction: "amen://ai/summarize-replies?postId={{postId}}"
                ),
                FollowUpSchedule(
                    triggerAfter: 2 * hour,
                    type: .detectRisingTension,
                    suggestion: "Your comment section may need attention. Review the conversation.",
                    actionLabel: "Review Comments",
                    deepLinkAction: "amen://post/comments?postId={{postId}}&highlight=tension"
                )
            ]

        // ── Event Recap ────────────────────────────────────────────────────
        case .eventRecap:
            return [
                FollowUpSchedule(
                    triggerAfter: 7 * day,
                    type: .saveAsMemory,
                    suggestion: "Save this event recap as a community memory your church can look back on.",
                    actionLabel: "Save as Memory",
                    deepLinkAction: "amen://memories/save"
                ),
                FollowUpSchedule(
                    triggerAfter: 7 * day,
                    type: .suggestFollowUpPost,
                    suggestion: "Ready to plan your next event? Start building on the momentum.",
                    actionLabel: "Plan Next Event",
                    deepLinkAction: "amen://compose?context=upcoming_event"
                ),
                FollowUpSchedule(
                    triggerAfter: 3 * day,
                    type: .repostToSpace,
                    suggestion: "Share this recap to a Space so your community can find it easily.",
                    actionLabel: "Repost to Space",
                    deepLinkAction: "amen://spaces/repost?postId={{postId}}"
                )
            ]

        // ── Teaching ───────────────────────────────────────────────────────
        case .teaching:
            return [
                FollowUpSchedule(
                    triggerAfter: 24 * hour,
                    type: .turnIntoNote,
                    suggestion: "Turn this teaching into a resource post your community can save and reference.",
                    actionLabel: "Turn into Resource",
                    deepLinkAction: "amen://resources/create-from-post?postId={{postId}}"
                ),
                FollowUpSchedule(
                    triggerAfter: 24 * hour,
                    type: .suggestResource,
                    suggestion: "Suggest a study guide follow-up so people can go deeper with this teaching.",
                    actionLabel: "Suggest Study Guide",
                    deepLinkAction: "amen://resources/study-guide?postId={{postId}}"
                ),
                FollowUpSchedule(
                    triggerAfter: 3 * day,
                    type: .repostToSpace,
                    suggestion: "Share this teaching to a relevant Space to reach more of your community.",
                    actionLabel: "Repost to Space",
                    deepLinkAction: "amen://spaces/repost?postId={{postId}}"
                )
            ]

        // ── Reflection ─────────────────────────────────────────────────────
        case .reflection:
            return [
                FollowUpSchedule(
                    triggerAfter: 24 * hour,
                    type: .turnIntoNote,
                    suggestion: "This reflection would make a meaningful Church Note. Turn it into one.",
                    actionLabel: "Turn into Note",
                    deepLinkAction: "amen://notes/create-from-post"
                )
            ]

        // ── Mission Update ──────────────────────────────────────────────────
        case .missionUpdate:
            return [
                FollowUpSchedule(
                    triggerAfter: 7 * day,
                    type: .suggestFollowUpPost,
                    suggestion: "A week in — share your next mission update to keep your supporters informed.",
                    actionLabel: "Post Update",
                    deepLinkAction: "amen://compose?context=mission_update"
                ),
                FollowUpSchedule(
                    triggerAfter: 14 * day,
                    type: .saveAsMemory,
                    suggestion: "Archive this update as a mission memory to document your journey.",
                    actionLabel: "Save as Memory",
                    deepLinkAction: "amen://memories/save"
                )
            ]

        // ── Announcement ────────────────────────────────────────────────────
        case .announcement:
            return [
                FollowUpSchedule(
                    triggerAfter: 24 * hour,
                    type: .suggestFollowUpPost,
                    suggestion: "Post a reminder for your upcoming event — don't let people miss it.",
                    actionLabel: "Post Reminder",
                    deepLinkAction: "amen://compose?context=event_reminder"
                )
            ]

        // ── Gratitude ────────────────────────────────────────────────────────
        case .gratitude:
            return [
                FollowUpSchedule(
                    triggerAfter: 7 * day,
                    type: .saveAsMemory,
                    suggestion: "Save this gratitude post as a personal memory to revisit on harder days.",
                    actionLabel: "Save as Memory",
                    deepLinkAction: "amen://memories/save"
                )
            ]

        // ── Resource ─────────────────────────────────────────────────────────
        case .resource:
            return [
                FollowUpSchedule(
                    triggerAfter: 3 * day,
                    type: .repostToSpace,
                    suggestion: "Share this resource to a Space where your community will benefit most.",
                    actionLabel: "Repost to Space",
                    deepLinkAction: "amen://spaces/repost?postId={{postId}}"
                )
            ]

        // ── General ──────────────────────────────────────────────────────────
        case .general:
            return []
        }
    }

    // MARK: - Schedule Follow-Ups

    /// Schedules follow-up suggestions for a post after it is published.
    ///
    /// Creates `PostFollowUp` records and persists them so the author sees
    /// them in their private notification feed at the right time.
    ///
    /// - Parameters:
    ///   - postId: The newly published post's ID.
    ///   - intent: The detected `PostIntent` for this post.
    ///   - mediaTypes: Array of media types in the post, e.g. `["video", "photo"]`.
    func scheduleFollowUps(
        for postId: String,
        intent: PostIntent,
        mediaTypes: [String]
    ) async {
        let definitions = schedules(for: intent, mediaTypes: mediaTypes)

        let newFollowUps: [PostFollowUp] = definitions.map { def in
            // Interpolate postId into deepLinkAction template
            let resolvedAction = def.deepLinkAction
                .replacingOccurrences(of: "{{postId}}", with: postId)

            return PostFollowUp(
                id: UUID().uuidString,
                postId: postId,
                triggerAfter: def.triggerAfter,
                type: def.type,
                suggestion: def.suggestion,
                actionLabel: def.actionLabel,
                deepLinkAction: resolvedAction,
                isDismissed: false,
                isCompleted: false
            )
        }

        // Optimistic local state update
        pendingFollowUps.append(contentsOf: newFollowUps)

        // TODO: Persist to server via URLSession:
        //   POST /api/followups/schedule
        //   Body: {
        //     "postId": postId,
        //     "followUps": newFollowUps.map { [
        //       "id": $0.id,
        //       "type": $0.type.rawValue,
        //       "triggerAfter": $0.triggerAfter,
        //       "deepLinkAction": $0.deepLinkAction
        //     ]}
        //   }
        //
        // Firebase/Firestore alternative:
        //   let db = Firestore.firestore()
        //   let batch = db.batch()
        //   newFollowUps.forEach { followUp in
        //     let ref = db.collection("followUps").document(followUp.id)
        //     batch.setData([...], forDocument: ref)
        //   }
        //   try await batch.commit()
    }

    // MARK: - Fetch Pending Follow-Ups

    /// Loads all pending (non-dismissed, non-completed) follow-ups for a user.
    ///
    /// Filters to only follow-ups whose trigger time has elapsed.
    ///
    /// - Parameter userId: The authenticated user's ID.
    func fetchPendingFollowUps(for userId: String) async {
        // TODO: Replace stub with real server/Firestore fetch:
        //   GET /api/followups/pending?userId=\(userId)
        //   Response: { "followUps": [ PostFollowUp JSON array ] }
        //
        // Firebase alternative:
        //   let db = Firestore.firestore()
        //   let snapshot = try await db.collection("followUps")
        //     .whereField("userId", isEqualTo: userId)
        //     .whereField("isDismissed", isEqualTo: false)
        //     .whereField("isCompleted", isEqualTo: false)
        //     .getDocuments()
        //   let fetched = snapshot.documents.compactMap { try? $0.data(as: PostFollowUp.self) }
        //   pendingFollowUps = fetched.filter { shouldTrigger($0) }

        // Local stub: filter already-loaded follow-ups by trigger time
        let now = Date()
        // For production: publishedAt would come from the post record
        // This stub assumes follow-ups were created at app launch for demonstration
        let _ = now   // silence unused warning in stub
    }

    // MARK: - Dismiss Follow-Up

    /// Marks a follow-up as dismissed by the author.
    ///
    /// Dismissed follow-ups are hidden from the author's feed but retained
    /// in the database for analytics and moderation review if needed.
    ///
    /// - Parameter id: The `PostFollowUp.id` to dismiss.
    func dismissFollowUp(id: String) async {
        // Optimistic local update
        if let idx = pendingFollowUps.firstIndex(where: { $0.id == id }) {
            pendingFollowUps[idx].isDismissed = true
        }
        pendingFollowUps.removeAll { $0.id == id && $0.isDismissed }

        // TODO: Persist dismissal to server:
        //   PATCH /api/followups/\(id)/dismiss
        //
        // Firebase alternative:
        //   try await Firestore.firestore()
        //     .collection("followUps").document(id)
        //     .updateData(["isDismissed": true])
    }

    // MARK: - Complete Follow-Up

    /// Marks a follow-up as completed after the author takes the suggested action.
    ///
    /// - Parameter id: The `PostFollowUp.id` to mark complete.
    func completeFollowUp(id: String) async {
        // Optimistic local update
        if let idx = pendingFollowUps.firstIndex(where: { $0.id == id }) {
            pendingFollowUps[idx].isCompleted = true
        }
        pendingFollowUps.removeAll { $0.id == id && $0.isCompleted }

        // TODO: Persist completion to server:
        //   PATCH /api/followups/\(id)/complete
        //
        // Firebase alternative:
        //   try await Firestore.firestore()
        //     .collection("followUps").document(id)
        //     .updateData(["isCompleted": true, "completedAt": Timestamp(date: Date())])
    }

    // MARK: - Tension Detection

    /// Analyzes a post's comment section for rising tension or conflict signals.
    ///
    /// Returns a tension score 0.0–1.0. This result is **author-only** and
    /// is never surfaced publicly or shown to other users.
    ///
    /// - Parameter postId: The post to analyze.
    /// - Returns: Tension score where 0.0 = peaceful, 1.0 = high conflict.
    func detectCommentTension(postId: String) async -> Double {
        // TODO: Replace with server-side NLP analysis:
        //   POST /api/posts/\(postId)/comment-tension
        //   Response: { "tensionScore": Double, "flaggedCommentIds": [String] }
        //
        // Local heuristic stub:
        // Would analyze loaded comments for:
        // - High frequency of question marks or exclamation marks
        // - Repeated negative sentiment words ("wrong", "disagree", "false")
        // - Reply depth spikes (argument threads)
        // - Repeated same-user activity (escalation pattern)
        return 0.0   // stub: no tension detected
    }

    // MARK: - Summarize Comment Themes

    /// Privately summarizes the main themes from a post's comment section.
    ///
    /// The returned strings are **author-only insight** — they are never
    /// shown in the feed, in comments, or to other users.
    ///
    /// - Parameter postId: The post whose comments to summarize.
    /// - Returns: Array of theme strings (e.g., `["People sharing their own testimonies",
    ///   "Questions about prayer timing", "Gratitude and encouragement"]`).
    func summarizeCommentThemes(postId: String) async -> [String] {
        // TODO: Replace with server-side AI summary:
        //   POST /api/posts/\(postId)/comment-themes
        //   Response: { "themes": [String] }
        //
        // Firebase Functions alternative:
        //   let result = try await Functions.functions()
        //     .httpsCallable("summarizeCommentThemes")
        //     .call(["postId": postId])
        //   return (result.data as? [String: Any])?["themes"] as? [String] ?? []
        return []   // stub: no themes available until server endpoint implemented
    }

    // MARK: - Helpers

    /// Returns `true` if a follow-up's trigger window has elapsed relative to a publish date.
    private func shouldTrigger(_ followUp: PostFollowUp, publishedAt: Date) -> Bool {
        let triggerDate = publishedAt.addingTimeInterval(followUp.triggerAfter)
        return Date() >= triggerDate
    }

    /// Returns only the pending follow-ups for a specific post.
    func pendingFollowUps(for postId: String) -> [PostFollowUp] {
        pendingFollowUps.filter {
            $0.postId == postId && !$0.isDismissed && !$0.isCompleted
        }
    }
}
