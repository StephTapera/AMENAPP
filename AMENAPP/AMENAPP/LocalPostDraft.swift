// LocalPostDraft.swift
// AMENAPP
//
// SwiftData model for locally-persisted CreatePost draft state.
// Dual-write alongside UserDefaults "autoSavedDraft" during migration.
// Unlike the UserDefaults key, this is userId-scoped — safe for account switching.
//
// Image DATA is not persisted here (too large). imageCount + imageAltTexts give
// the recovery UI enough info to notify the user that photos need re-selection.

import SwiftData
import Foundation
import FirebaseAuth

// MARK: - LocalPostDraftPhase

enum LocalPostDraftPhase: String, Codable {
    case editing      = "editing"
    case publishReady = "publish_ready"
    case publishing   = "publishing"
    case published    = "published"
    case failed       = "failed"
}

// MARK: - LocalPostDraftUploadPhase

enum LocalPostDraftUploadPhase: String, Codable {
    case idle       = "idle"
    case uploading  = "uploading"
    case completed  = "completed"
    case failed     = "failed"
}

// MARK: - LocalPostDraftModerationPhase

enum LocalPostDraftModerationPhase: String, Codable {
    case pending      = "pending"
    case passed       = "passed"
    case blocked      = "blocked"
    case editRequired = "edit_required"
}

// MARK: - LocalPostDraft

@Model
final class LocalPostDraft {
    var id: UUID
    var userId: String
    var postText: String
    var categoryRawValue: String
    var topicTag: String
    var linkURL: String
    var pollQuestion: String
    var pollOptionsJSON: String
    var pollDurationRawValue: String
    var showingPoll: Bool
    var isThreadMode: Bool
    var threadPostsJSON: String
    var currentThreadIndex: Int
    var postVisibilityRawValue: String
    var commentPermissionRawValue: String
    var attachedVerseReference: String
    var attachedVerseText: String
    var taggedChurchId: String
    var taggedChurchName: String
    var hideEngagementCounts: Bool
    var hasSensitiveContent: Bool
    var sensitiveContentReason: String
    var imageAltTextsJSON: String
    var imageCount: Int
    var witnessAttachmentJSON: String?
    var mediaMetadataDraftJSON: String?
    var phaseRawValue: String
    var uploadPhaseRawValue: String
    var moderationPhaseRawValue: String
    var idempotencyToken: String?
    var inFlightPostId: String?
    var createdAt: Date
    var updatedAt: Date

    init(userId: String) {
        self.id = UUID()
        self.userId = userId
        self.postText = ""
        self.categoryRawValue = ""
        self.topicTag = ""
        self.linkURL = ""
        self.pollQuestion = ""
        self.pollOptionsJSON = "[\"\",\"\"]"
        self.pollDurationRawValue = ""
        self.showingPoll = false
        self.isThreadMode = false
        self.threadPostsJSON = "[\"\"]"
        self.currentThreadIndex = 0
        self.postVisibilityRawValue = ""
        self.commentPermissionRawValue = ""
        self.attachedVerseReference = ""
        self.attachedVerseText = ""
        self.taggedChurchId = ""
        self.taggedChurchName = ""
        self.hideEngagementCounts = false
        self.hasSensitiveContent = false
        self.sensitiveContentReason = ""
        self.imageAltTextsJSON = "[]"
        self.imageCount = 0
        self.witnessAttachmentJSON = nil
        self.mediaMetadataDraftJSON = nil
        self.phaseRawValue = LocalPostDraftPhase.editing.rawValue
        self.uploadPhaseRawValue = LocalPostDraftUploadPhase.idle.rawValue
        self.moderationPhaseRawValue = LocalPostDraftModerationPhase.pending.rawValue
        self.idempotencyToken = nil
        self.inFlightPostId = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var phase: LocalPostDraftPhase {
        get { LocalPostDraftPhase(rawValue: phaseRawValue) ?? .editing }
        set { phaseRawValue = newValue.rawValue; updatedAt = Date() }
    }

    var pollOptions: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(pollOptionsJSON.utf8))) ?? ["", ""] }
        set { pollOptionsJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\",\"\"]" }
    }

    var threadPosts: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(threadPostsJSON.utf8))) ?? [""] }
        set { threadPostsJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]" }
    }

    var imageAltTexts: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(imageAltTextsJSON.utf8))) ?? [] }
        set { imageAltTextsJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }
    }

    var hasContent: Bool {
        !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || showingPoll
            || isThreadMode
            || witnessAttachmentJSON != nil
    }
}

// MARK: - CreatePostDraftStore

/// Shared ModelContainer for LocalPostDraft persistence.
/// Uses the singleton pattern so both CreatePostView and AppLifecycleManager
/// can access it without needing a SwiftUI environment injection.
@MainActor
final class CreatePostDraftStore {
    static let shared = CreatePostDraftStore()

    let container: ModelContainer

    private init() {
        let schema = Schema([LocalPostDraft.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("CreatePostDraftStore: failed to initialize ModelContainer: \(error)")
        }
    }

    // MARK: - Read

    /// Returns the active (editing-phase) draft for the current user.
    func draftForCurrentUser() -> LocalPostDraft? {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return nil }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LocalPostDraft>(
            predicate: #Predicate { $0.userId == uid && $0.phaseRawValue == "editing" },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: - Write

    /// Upserts the draft for the current user. Creates one if none exists.
    func save(
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
        mediaMetadataDraftJSON: String?,
        uploadPhaseRawValue: String = LocalPostDraftUploadPhase.idle.rawValue,
        moderationPhaseRawValue: String = LocalPostDraftModerationPhase.pending.rawValue,
        idempotencyToken: String? = nil,
        inFlightPostId: String? = nil
    ) {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LocalPostDraft>(
            predicate: #Predicate { $0.userId == uid && $0.phaseRawValue == "editing" }
        )
        let existing = try? context.fetch(descriptor).first
        let draft = existing ?? {
            let d = LocalPostDraft(userId: uid)
            context.insert(d)
            return d
        }()

        draft.postText = postText
        draft.categoryRawValue = categoryRawValue
        draft.topicTag = topicTag
        draft.linkURL = linkURL
        draft.pollQuestion = pollQuestion
        draft.pollOptions = pollOptions
        draft.pollDurationRawValue = pollDurationRawValue
        draft.showingPoll = showingPoll
        draft.isThreadMode = isThreadMode
        draft.threadPosts = threadPosts
        draft.currentThreadIndex = currentThreadIndex
        draft.postVisibilityRawValue = postVisibilityRawValue
        draft.commentPermissionRawValue = commentPermissionRawValue
        draft.attachedVerseReference = attachedVerseReference
        draft.attachedVerseText = attachedVerseText
        draft.taggedChurchId = taggedChurchId
        draft.taggedChurchName = taggedChurchName
        draft.hideEngagementCounts = hideEngagementCounts
        draft.hasSensitiveContent = hasSensitiveContent
        draft.sensitiveContentReason = sensitiveContentReason
        draft.imageAltTexts = imageAltTexts
        draft.imageCount = imageCount
        draft.witnessAttachmentJSON = witnessAttachmentJSON
        draft.mediaMetadataDraftJSON = mediaMetadataDraftJSON
        draft.uploadPhaseRawValue = uploadPhaseRawValue
        draft.moderationPhaseRawValue = moderationPhaseRawValue
        draft.idempotencyToken = idempotencyToken
        draft.inFlightPostId = inFlightPostId
        draft.updatedAt = Date()

        try? context.save()
    }

    // MARK: - Phase update (called without re-saving all content fields)

    func updatePhase(
        uploadPhaseRawValue: String,
        moderationPhaseRawValue: String,
        idempotencyToken: String?,
        inFlightPostId: String?
    ) {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LocalPostDraft>(
            predicate: #Predicate { $0.userId == uid && $0.phaseRawValue == "editing" }
        )
        guard let draft = try? context.fetch(descriptor).first else { return }
        draft.uploadPhaseRawValue = uploadPhaseRawValue
        draft.moderationPhaseRawValue = moderationPhaseRawValue
        draft.idempotencyToken = idempotencyToken
        draft.inFlightPostId = inFlightPostId
        draft.updatedAt = Date()
        try? context.save()
    }

    // MARK: - Clear

    /// Deletes all drafts for the current user. Called on publish success or explicit discard.
    func clearDraftForCurrentUser() {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
        deleteDrafts(forUserId: uid)
    }

    /// Sign-out cleanup — deletes all drafts for the given userId.
    func cleanupDrafts(forUserId userId: String) {
        deleteDrafts(forUserId: userId)
    }

    private func deleteDrafts(forUserId userId: String) {
        let context = ModelContext(container)
        let uid = userId
        let descriptor = FetchDescriptor<LocalPostDraft>(
            predicate: #Predicate { $0.userId == uid }
        )
        let drafts = (try? context.fetch(descriptor)) ?? []
        drafts.forEach { context.delete($0) }
        try? context.save()
    }
}
