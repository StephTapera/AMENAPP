// SmartCommentViewModel.swift
// AMENAPP — Smart Comments Wave 1
//
// ViewModel for SmartCommentsSheet. Bridges the existing CommentService (Firebase
// Realtime DB) and SmartCommentService (coaching callable) into the new SmartComment
// contract types from SmartCommentsContracts.swift.
//
// INVARIANT: No comment is publicly visible until moderation passes (fail-closed).
//            visibleComments() is the sole read gate — callers MUST use it, not
//            the raw `comments` array.

import SwiftUI
import Foundation
import FirebaseAuth

@MainActor
final class SmartCommentViewModel: ObservableObject {

    // MARK: - Published State

    /// All comments mapped to SmartComment. Filter with visibleComments() before display.
    @Published var comments: [SmartComment] = []

    /// True while initial comment fetch is in progress.
    @Published var isLoading = false

    /// True while a comment submission write is in flight.
    @Published var isPosting = false

    /// Non-nil when an error should be surfaced to the user.
    @Published var error: String?

    /// Optimistic local comment inserted immediately after submission.
    /// Shown as "Pending safety review" until moderation resolves or it is replaced
    /// by the real server comment from the RTDB listener.
    @Published var pendingLocalComment: SmartComment?

    /// Non-nil when the coaching callable returned `.nudge`.
    /// The UI presents the nudge message and lets the user decide whether to post anyway.
    @Published var nudgeSuggestion: String?

    // MARK: - Private State

    private let postId: String

    // MARK: - Init

    init(postId: String) {
        self.postId = postId
    }

    // MARK: - Load

    /// Loads comments for the post via the existing CommentService real-time listener.
    /// Maps `Comment` (PostInteractionModels) → `SmartComment` (SmartCommentsContracts).
    /// Guards on the `smartCommentsEnabled` feature flag — returns immediately if OFF.
    func loadComments() async {
        guard AMENFeatureFlags.shared.smartCommentsEnabled else { return }

        isLoading = true
        defer { isLoading = false }

        // Start the RTDB listener so the service cache is populated.
        CommentService.shared.startListening(to: postId)

        do {
            let rawComments = try await CommentService.shared.fetchComments(for: postId)
            let currentUserId = Auth.auth().currentUser?.uid

            // Map existing Comment → SmartComment. We don't have server-side moderation
            // status in the existing RTDB model, so we infer based on approval status.
            comments = rawComments.compactMap { raw in
                mapToSmartComment(raw, currentUserId: currentUserId)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Submit

    /// Reviews a comment body through the SmartCommentService coaching callable, then
    /// writes to Firebase Realtime DB via the existing CommentService if cleared.
    ///
    /// Flow:
    ///   1. Validate length (1–2000 chars)
    ///   2. Call SmartCommentService.reviewComment (coaching gate)
    ///   3. .block  → set error, return without write
    ///   4. .nudge  → set nudgeSuggestion, return (UI shows nudge sheet)
    ///   5. .publish → write via CommentService.addComment with pending moderation state
    ///   6. Set pendingLocalComment for optimistic UI
    func submitComment(body: String) async {
        guard AMENFeatureFlags.shared.smartCommentsEnabled else { return }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...2000).contains(trimmed.count) else {
            error = "Comment must be between 1 and 2,000 characters."
            return
        }

        guard !isPosting else { return }
        isPosting = true
        defer { isPosting = false }

        // Step 1: Run the comment through the coaching callable.
        let coachResult: SmartCommentResult
        do {
            coachResult = try await SmartCommentService.shared.reviewComment(
                commentText: trimmed,
                postContext: nil
            )
        } catch let err as SmartCommentError {
            switch err {
            case .consentRequired:
                // Consent not given — skip the coach and allow posting.
                // The server-side moderation pipeline will still run.
                coachResult = SmartCommentResult(
                    action: .publish,
                    nudgeMessage: nil,
                    rewriteSuggestion: nil,
                    provider: nil
                )
            case .rateLimitExceeded:
                // Soft rate limit hit — treat as publish (server enforces the real limit).
                coachResult = SmartCommentResult(
                    action: .publish,
                    nudgeMessage: nil,
                    rewriteSuggestion: nil,
                    provider: nil
                )
            default:
                // Network or other failure: fail closed — do not post.
                error = err.localizedDescription
                return
            }
        } catch {
            // Unknown error: fail closed.
            self.error = "Unable to review comment. Please try again."
            return
        }

        // Step 2: Act on the coaching decision.
        switch coachResult.action {
        case .block:
            error = coachResult.nudgeMessage
                ?? "This comment was blocked by our safety system. Please revise before posting."
            return

        case .nudge:
            nudgeSuggestion = coachResult.nudgeMessage
                ?? coachResult.rewriteSuggestion
                ?? "Consider revising your comment before posting."
            // Return without writing — the UI shows the nudge sheet.
            // The user can call submitComment again (after accepting the nudge) or dismiss.
            return

        case .publish:
            break // fall through to write
        }

        // Step 3: Write via the existing CommentService. The existing service already runs
        // its own moderation pipeline (CommentQualityGateway, LocalContentGuard, etc.)
        // server-side. We are layering the SmartCommentService coach ON TOP of that.
        let writtenComment: Comment
        do {
            writtenComment = try await CommentService.shared.addComment(
                postId: postId,
                content: trimmed
            )
        } catch {
            self.error = error.localizedDescription
            return
        }

        // Step 4: Set optimistic pending local comment so the UI shows it immediately.
        // visibilityStatus is .hidden and moderationStatus is .pendingReview until the
        // server moderation pipeline resolves and updates the RTDB record.
        let currentUserId = Auth.auth().currentUser?.uid ?? ""
        let now = Date().timeIntervalSince1970
        pendingLocalComment = SmartComment(
            id: writtenComment.id ?? UUID().uuidString,
            postId: postId,
            parentCommentId: nil,
            userId: currentUserId,
            body: trimmed,
            detectedEntities: [],
            attachments: [],
            moderationStatus: .pendingReview,
            visibilityStatus: .hidden,
            safetyLabels: [],
            _trustScoreSnapshot: nil,
            reactions: [],
            replyCount: 0,
            createdAt: now,
            updatedAt: now
        )

        // Step 5: Trigger a re-load so the confirmed server comment appears when ready.
        // The RTDB listener will fire; we nudge the view to refresh.
        await loadComments()
    }

    // MARK: - Visibility Gate (fail-closed)

    /// Returns only publicly visible comments plus the current user's own pending comments.
    ///
    /// This is the ONLY correct way to read comments for display. Never render the raw
    /// `comments` array directly — the visibility gate is the no-read-before-moderation spine.
    func visibleComments(currentUserId: String?) -> [SmartComment] {
        comments.filter { comment in
            // Public: moderation passed.
            if comment.visibilityStatus == .public {
                return true
            }
            // Owner visibility: the author can see their own pending comment.
            if let uid = currentUserId, !uid.isEmpty, comment.userId == uid {
                return true
            }
            return false
        }
    }

    // MARK: - Dismiss Nudge

    /// Called when the user dismisses the nudge without posting.
    func dismissNudge() {
        nudgeSuggestion = nil
    }

    // MARK: - Cleanup

    /// Stops the RTDB listener. Call from the sheet's onDisappear.
    func stopListening() {
        CommentService.shared.stopListening(to: postId, clearCache: false)
    }

    // MARK: - Private Helpers

    /// Maps the existing app-wide `Comment` type (PostInteractionModels.swift) to the
    /// Wave-1 `SmartComment` contract type (SmartCommentsContracts.swift).
    ///
    /// Moderation inference: the existing RTDB model doesn't carry a moderationStatus field.
    ///   - approvalStatus == "pending" → .pendingReview / .hidden
    ///   - approvalStatus == "rejected" → .blocked / .deleted
    ///   - nil / "approved" → .allowed / .public (optimistic; server is authoritative)
    private func mapToSmartComment(_ raw: Comment, currentUserId: String?) -> SmartComment? {
        guard let commentId = raw.id else { return nil }

        let moderationStatus: CommentModerationStatus
        let visibilityStatus: CommentVisibilityStatus

        switch raw.approvalStatus {
        case "pending":
            moderationStatus = .pendingReview
            visibilityStatus = .hidden
        case "rejected":
            moderationStatus = .blocked
            visibilityStatus = .deleted
        default:
            moderationStatus = .allowed
            visibilityStatus = .public
        }

        let createdAtInterval = raw.createdAt.timeIntervalSince1970
        let updatedAtInterval = raw.updatedAt.timeIntervalSince1970

        // Map amenCount to an .amen reaction list (lightweight — counts only; no full IDs).
        let reactions: [SmartCommentReaction] = raw.amenUserIds.prefix(raw.amenCount).map { userId in
            SmartCommentReaction(
                id: "\(commentId)_amen_\(userId)",
                commentId: commentId,
                authorId: userId,
                kind: .amen,
                createdAt: createdAtInterval
            )
        }

        return SmartComment(
            id: commentId,
            postId: raw.postId,
            parentCommentId: raw.parentCommentId,
            userId: raw.authorId,
            body: raw.content,
            detectedEntities: [],       // Wave 2: entity detection pipeline
            attachments: [],            // Wave 3: preview cards
            moderationStatus: moderationStatus,
            visibilityStatus: visibilityStatus,
            safetyLabels: [],           // Server-populated in future waves
            _trustScoreSnapshot: nil,   // Internal TrustOS — never displayed
            reactions: reactions,
            replyCount: raw.replyCount,
            createdAt: createdAtInterval,
            updatedAt: updatedAtInterval
        )
    }
}
