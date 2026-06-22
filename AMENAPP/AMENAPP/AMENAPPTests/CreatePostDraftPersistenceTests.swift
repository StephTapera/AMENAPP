#if canImport(Testing)
// CreatePostDraftPersistenceTests.swift
// AMENAPPTests
//
// Phase 2B SwiftData-backed draft persistence contracts.

import Foundation

#if canImport(Testing)
import Testing
import SwiftData
@testable import AMENAPP

// MARK: - Helpers

private func makeInMemoryStore() throws -> ModelContainer {
    let schema = Schema([LocalPostDraft.self, LocalPostDraftMediaItem.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: config)
}

@discardableResult
private func makeDraft(userId: String, postText: String = "Test content", context: ModelContext) -> LocalPostDraft {
    let draft = LocalPostDraft(userId: userId)
    draft.postText = postText
    context.insert(draft)
    try? context.save()
    return draft
}

// MARK: - CreatePostDraftPersistenceTests

@Suite("CreatePostDraft persistence")
struct CreatePostDraftPersistenceTests {

    // MARK: 1. userId scoping

    @Test("Draft fetch is scoped to userId — different users don't see each other's drafts")
    func userIdScoping() throws {
        let container = try makeInMemoryStore()
        let context = ModelContext(container)

        makeDraft(userId: "alice-uid", postText: "Alice draft", context: context)
        makeDraft(userId: "bob-uid", postText: "Bob draft", context: context)

        let aliceDescriptor = FetchDescriptor<LocalPostDraft>(
            predicate: #Predicate { $0.userId == "alice-uid" }
        )
        let bobDescriptor = FetchDescriptor<LocalPostDraft>(
            predicate: #Predicate { $0.userId == "bob-uid" }
        )

        let aliceFetched = try context.fetch(aliceDescriptor)
        let bobFetched = try context.fetch(bobDescriptor)

        #expect(aliceFetched.count == 1)
        #expect(aliceFetched.first?.postText == "Alice draft")
        #expect(bobFetched.count == 1)
        #expect(bobFetched.first?.postText == "Bob draft")
        #expect(aliceFetched.first?.userId != "bob-uid")
        #expect(bobFetched.first?.userId != "alice-uid")
    }

    @Test("Cleanup by userId deletes only that user's drafts")
    func cleanupScopedToUser() throws {
        let container = try makeInMemoryStore()
        let context = ModelContext(container)

        makeDraft(userId: "alice-uid", context: context)
        makeDraft(userId: "bob-uid", context: context)

        let aliceDescriptor = FetchDescriptor<LocalPostDraft>(
            predicate: #Predicate { $0.userId == "alice-uid" }
        )
        let aliceDrafts = try context.fetch(aliceDescriptor)
        aliceDrafts.forEach { context.delete($0) }
        try context.save()

        let allDescriptor = FetchDescriptor<LocalPostDraft>()
        let remaining = try context.fetch(allDescriptor)
        #expect(remaining.count == 1)
        #expect(remaining.first?.userId == "bob-uid")
    }

    // MARK: 2. Media item persistence

    @Test("LocalPostDraftMediaItem persists and cascades with draft deletion")
    func mediaItemPersistence() throws {
        let container = try makeInMemoryStore()
        let context = ModelContext(container)

        let draft = makeDraft(userId: "test-uid", context: context)

        let item1 = LocalPostDraftMediaItem(
            draftId: draft.id,
            sortOrder: 0,
            altText: "Sunrise photo",
            localFilePath: "/tmp/draft_img0.jpg",
            sourceTypeRawValue: "library",
            mimeType: "image/jpeg"
        )
        let item2 = LocalPostDraftMediaItem(
            draftId: draft.id,
            sortOrder: 1,
            altText: "Sunset video",
            localFilePath: "/tmp/draft_vid1.mp4",
            sourceTypeRawValue: "camera",
            mimeType: "video/mp4"
        )
        draft.mediaItems = [item1, item2]
        try context.save()

        let descriptor = FetchDescriptor<LocalPostDraft>(
            predicate: #Predicate { $0.userId == "test-uid" }
        )
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        let fetchedDraft = fetched[0]
        #expect(fetchedDraft.mediaItems.count == 2)

        let sorted = fetchedDraft.mediaItems.sorted { $0.sortOrder < $1.sortOrder }
        #expect(sorted[0].altText == "Sunrise photo")
        #expect(sorted[0].mimeType == "image/jpeg")
        #expect(sorted[1].sourceTypeRawValue == "camera")

        // Cascade delete
        context.delete(fetchedDraft)
        try context.save()

        let mediaDescriptor = FetchDescriptor<LocalPostDraftMediaItem>()
        let orphans = try context.fetch(mediaDescriptor)
        #expect(orphans.isEmpty, "Cascade delete should remove all media items")
    }

    // MARK: 3. Idempotency token

    @Test("uploadPhaseRawValue and idempotencyToken persist through save/fetch cycle")
    func idempotencyTokenPersistence() throws {
        let container = try makeInMemoryStore()
        let context = ModelContext(container)

        let draft = makeDraft(userId: "test-uid", context: context)
        let token = UUID().uuidString
        draft.uploadPhaseRawValue = LocalPostDraftUploadPhase.uploading.rawValue
        draft.idempotencyToken = token
        draft.inFlightPostId = token
        try context.save()

        let context2 = ModelContext(container)
        let descriptor = FetchDescriptor<LocalPostDraft>(
            predicate: #Predicate { $0.userId == "test-uid" }
        )
        let fetched = try context2.fetch(descriptor)
        #expect(fetched.count == 1)
        let fetchedDraft = fetched[0]
        #expect(fetchedDraft.uploadPhaseRawValue == "uploading")
        #expect(fetchedDraft.idempotencyToken == token)
        #expect(fetchedDraft.inFlightPostId == token)
    }

    @Test("idempotencyToken is nil after successful publish reset")
    func idempotencyTokenClearedOnSuccess() throws {
        let container = try makeInMemoryStore()
        let context = ModelContext(container)

        let draft = makeDraft(userId: "test-uid", context: context)
        draft.uploadPhaseRawValue = LocalPostDraftUploadPhase.uploading.rawValue
        draft.idempotencyToken = UUID().uuidString
        draft.inFlightPostId = draft.idempotencyToken
        try context.save()

        draft.uploadPhaseRawValue = LocalPostDraftUploadPhase.completed.rawValue
        draft.idempotencyToken = nil
        draft.inFlightPostId = nil
        try context.save()

        let context2 = ModelContext(container)
        let descriptor = FetchDescriptor<LocalPostDraft>(
            predicate: #Predicate { $0.userId == "test-uid" }
        )
        let fetched = try context2.fetch(descriptor)
        let fetchedDraft = fetched[0]
        #expect(fetchedDraft.idempotencyToken == nil)
        #expect(fetchedDraft.inFlightPostId == nil)
        #expect(fetchedDraft.uploadPhaseRawValue == "completed")
    }

    // MARK: 4. Publish success clears draft

    @Test("Publish success: draft is deleted from store")
    func publishSuccessClearsDraft() throws {
        let container = try makeInMemoryStore()
        let context = ModelContext(container)

        makeDraft(userId: "publisher-uid", context: context)

        let descriptor = FetchDescriptor<LocalPostDraft>(
            predicate: #Predicate { $0.userId == "publisher-uid" }
        )
        let before = try context.fetch(descriptor)
        #expect(before.count == 1)

        before.forEach { context.delete($0) }
        try context.save()

        let after = try context.fetch(descriptor)
        #expect(after.isEmpty, "Draft must be cleared after successful publish")
    }

    // MARK: 5. Discard clears draft

    @Test("Explicit discard removes draft from store")
    func discardClearsDraft() throws {
        let container = try makeInMemoryStore()
        let context = ModelContext(container)

        makeDraft(userId: "discarder-uid", context: context)

        let descriptor = FetchDescriptor<LocalPostDraft>(
            predicate: #Predicate { $0.userId == "discarder-uid" }
        )
        let drafts = try context.fetch(descriptor)
        drafts.forEach { context.delete($0) }
        try context.save()

        let remaining = try context.fetch(descriptor)
        #expect(remaining.isEmpty, "Draft must be gone after explicit discard")
    }

    // MARK: 6. Failed upload keeps draft

    @Test("Failed upload preserves draft content for retry")
    func failedUploadKeepsDraft() throws {
        let container = try makeInMemoryStore()
        let context = ModelContext(container)

        let draft = makeDraft(userId: "retry-uid", postText: "Let all that you do be done in love.", context: context)
        let originalText = draft.postText

        draft.uploadPhaseRawValue = LocalPostDraftUploadPhase.failed.rawValue
        draft.idempotencyToken = nil
        draft.inFlightPostId = nil
        try context.save()

        let context2 = ModelContext(container)
        let descriptor = FetchDescriptor<LocalPostDraft>(
            predicate: #Predicate { $0.userId == "retry-uid" }
        )
        let fetched = try context2.fetch(descriptor)
        #expect(fetched.count == 1, "Draft must survive a failed upload")
        let fetchedDraft = fetched[0]
        #expect(fetchedDraft.postText == originalText, "Draft content must be intact after upload failure")
        #expect(fetchedDraft.uploadPhaseRawValue == "failed")
        #expect(fetchedDraft.idempotencyToken == nil)
    }

    // MARK: 7. hasContent guard

    @Test("Empty draft does not satisfy hasContent")
    func emptyDraftHasNoContent() {
        let draft = LocalPostDraft(userId: "test-uid")
        #expect(!draft.hasContent)
    }

    @Test("Draft with postText satisfies hasContent")
    func draftWithTextHasContent() {
        let draft = LocalPostDraft(userId: "test-uid")
        draft.postText = "Let all that you do be done in love."
        #expect(draft.hasContent)
    }

    @Test("Draft with poll satisfies hasContent even if postText is empty")
    func draftWithPollHasContent() {
        let draft = LocalPostDraft(userId: "test-uid")
        draft.showingPoll = true
        #expect(draft.hasContent)
    }

    // MARK: 8. Moderation phase

    @Test("Moderation phase defaults to pending")
    func moderationPhaseDefault() {
        let draft = LocalPostDraft(userId: "test-uid")
        #expect(draft.moderationPhaseRawValue == "pending")
    }

    @Test("Moderation phase persists blocked state")
    func moderationPhaseBlockedPersists() throws {
        let container = try makeInMemoryStore()
        let context = ModelContext(container)

        let draft = makeDraft(userId: "flagged-uid", context: context)
        draft.moderationPhaseRawValue = LocalPostDraftModerationPhase.blocked.rawValue
        draft.uploadPhaseRawValue = LocalPostDraftUploadPhase.idle.rawValue
        try context.save()

        let context2 = ModelContext(container)
        let descriptor = FetchDescriptor<LocalPostDraft>(
            predicate: #Predicate { $0.userId == "flagged-uid" }
        )
        let fetched = try context2.fetch(descriptor)
        let fetchedDraft = fetched[0]
        #expect(fetchedDraft.moderationPhaseRawValue == "blocked")
    }
}

#endif

#endif
