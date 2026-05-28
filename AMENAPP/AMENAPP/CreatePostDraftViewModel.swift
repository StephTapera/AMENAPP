// CreatePostDraftViewModel.swift
// AMENAPP
//
// @Observable ViewModel that owns the durable phase state for CreatePostView.
// Acts as the bridge between @State working copies and SwiftData persistence.
//
// Lifecycle contract:
//   autoSaveDraft()      → persistSnapshot(...)   — @State working copy → SwiftData
//   checkForDraftRecovery() → restoreIfAvailable() — SwiftData → @State (caller restores)
//   clearRecoveredDraft()   → clearDraft()        — discards both stores
//   publishPost() start    → markPublishing(token:)
//   publish success        → markPublished()       — clears draft
//   publish failure        → markFailed()          — keeps draft for retry
//   moderation blocked     → markModerationBlocked()

import Foundation
import Observation

// MARK: - CreatePostDraftViewModel

@Observable
@MainActor
final class CreatePostDraftViewModel {

    // MARK: - Phase state (all durable)

    private(set) var uploadPhase: LocalPostDraftUploadPhase = .idle
    private(set) var moderationPhase: LocalPostDraftModerationPhase = .pending
    private(set) var idempotencyToken: String?
    private(set) var inFlightPostId: String?

    // MARK: - Derived state

    var hasFailedUpload: Bool { uploadPhase == .failed }
    var isModerationBlocked: Bool {
        moderationPhase == .blocked || moderationPhase == .editRequired
    }

    // MARK: - Publish lifecycle transitions

    /// Called immediately when publish begins. Persists the token so a restart can detect
    /// an in-flight post and avoid duplicate submission.
    func markPublishing(token: String) {
        idempotencyToken = token
        inFlightPostId = token
        uploadPhase = .uploading
        flushPhaseToStore()
    }

    /// Called on successful Firestore write. Clears the draft so recovery never resurfaces it.
    func markPublished() {
        idempotencyToken = nil
        inFlightPostId = nil
        uploadPhase = .completed
        moderationPhase = .passed
        CreatePostDraftStore.shared.clearDraftForCurrentUser()
        resetPhaseState()
    }

    /// Called on upload / network error. Keeps draft content so the user can retry.
    func markFailed() {
        idempotencyToken = nil
        inFlightPostId = nil
        uploadPhase = .failed
        flushPhaseToStore()
    }

    /// Called when user cancels an in-progress publish attempt. Keeps the draft content.
    func cancelPublishing() {
        idempotencyToken = nil
        inFlightPostId = nil
        uploadPhase = .idle
        flushPhaseToStore()
    }

    /// Called when content moderation returns a hard block.
    func markModerationBlocked() {
        idempotencyToken = nil
        inFlightPostId = nil
        moderationPhase = .blocked
        uploadPhase = .idle
        flushPhaseToStore()
    }

    /// Called when moderation requires edits before the post can go through.
    func markModerationEditRequired() {
        idempotencyToken = nil
        inFlightPostId = nil
        moderationPhase = .editRequired
        uploadPhase = .idle
        flushPhaseToStore()
    }

    // MARK: - Snapshot persistence

    /// Syncs the current @State working copy into SwiftData, augmenting with phase state.
    /// Called from autoSaveDraft() instead of calling CreatePostDraftStore.shared.save() directly.
    func persistSnapshot(
        postText: String,
        categoryRawValue: String,
        topicTag: String,
        linkURL: String,
        pollQuestion: String,
        pollOptions: [String],
        pollDurationRawValue: String,
        showingPoll: Bool,
        isThreadMode: Bool,
        threadPosts: [String],
        currentThreadIndex: Int,
        postVisibilityRawValue: String,
        commentPermissionRawValue: String,
        attachedVerseReference: String,
        attachedVerseText: String,
        taggedChurchId: String,
        taggedChurchName: String,
        hideEngagementCounts: Bool,
        hasSensitiveContent: Bool,
        sensitiveContentReason: String,
        imageAltTexts: [String],
        imageCount: Int,
        witnessAttachmentJSON: String?,
        mediaMetadataDraftJSON: String?
    ) {
        CreatePostDraftStore.shared.save(
            postText: postText,
            categoryRawValue: categoryRawValue,
            topicTag: topicTag,
            linkURL: linkURL,
            pollQuestion: pollQuestion,
            pollOptions: pollOptions,
            pollDurationRawValue: pollDurationRawValue,
            showingPoll: showingPoll,
            isThreadMode: isThreadMode,
            threadPosts: threadPosts,
            currentThreadIndex: currentThreadIndex,
            postVisibilityRawValue: postVisibilityRawValue,
            commentPermissionRawValue: commentPermissionRawValue,
            attachedVerseReference: attachedVerseReference,
            attachedVerseText: attachedVerseText,
            taggedChurchId: taggedChurchId,
            taggedChurchName: taggedChurchName,
            hideEngagementCounts: hideEngagementCounts,
            hasSensitiveContent: hasSensitiveContent,
            sensitiveContentReason: sensitiveContentReason,
            imageAltTexts: imageAltTexts,
            imageCount: imageCount,
            witnessAttachmentJSON: witnessAttachmentJSON,
            mediaMetadataDraftJSON: mediaMetadataDraftJSON,
            uploadPhaseRawValue: uploadPhase.rawValue,
            moderationPhaseRawValue: moderationPhase.rawValue,
            idempotencyToken: idempotencyToken,
            inFlightPostId: inFlightPostId
        )
    }

    // MARK: - Restore

    /// Attempts to restore phase state from SwiftData. Returns the draft if found and < 24 h old.
    /// Caller reads content fields from the returned draft and restores @State vars.
    func restoreIfAvailable() -> LocalPostDraft? {
        guard let sd = CreatePostDraftStore.shared.draftForCurrentUser(),
              sd.hasContent,
              Date().timeIntervalSince(sd.updatedAt) < 86400 else {
            return nil
        }
        uploadPhase = LocalPostDraftUploadPhase(rawValue: sd.uploadPhaseRawValue) ?? .idle
        moderationPhase = LocalPostDraftModerationPhase(rawValue: sd.moderationPhaseRawValue) ?? .pending
        idempotencyToken = sd.idempotencyToken
        inFlightPostId = sd.inFlightPostId
        return sd
    }

    // MARK: - Clear

    /// Discards the SwiftData draft and resets all phase state.
    func clearDraft() {
        CreatePostDraftStore.shared.clearDraftForCurrentUser()
        UserDefaults.standard.removeObject(forKey: "autoSavedDraft")
        resetPhaseState()
    }

    // MARK: - Private helpers

    private func flushPhaseToStore() {
        CreatePostDraftStore.shared.updatePhase(
            uploadPhaseRawValue: uploadPhase.rawValue,
            moderationPhaseRawValue: moderationPhase.rawValue,
            idempotencyToken: idempotencyToken,
            inFlightPostId: inFlightPostId
        )
    }

    private func resetPhaseState() {
        uploadPhase = .idle
        moderationPhase = .pending
        idempotencyToken = nil
        inFlightPostId = nil
    }
}
