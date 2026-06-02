//
//  RepliesTests.swift
//  AMENAPPTests
//
//  Unit tests for the Replies tab pure logic:
//    - ReplyFilter.matches — all filter/context combinations
//    - ReplyThread.canOpenThread — post availability gate
//    - ReplyThread.replyTargetDisplay — username fallback chain
//    - ReplyThread.previewText — parent vs post content priority
//    - ReplyVisibilityState — banner text and icon correctness
//    - Pagination trigger — isLastFilteredItem guard logic
//
//  Firebase is NOT imported. All tests exercise structs/enums with no I/O.
//

import Foundation
import Testing
@testable import AMENAPP

// MARK: - Helpers

private func makeComment(
    id: String = "c1",
    postId: String = "p1",
    authorId: String = "u1",
    content: String = "Test comment",
    parentCommentId: String? = nil
) -> AMENAPP.Comment {
    AMENAPP.Comment(
        id: id,
        postId: postId,
        authorId: authorId,
        authorName: "Test User",
        authorUsername: "testuser",
        authorInitials: "TU",
        authorProfileImageURL: nil,
        content: content,
        createdAt: Date(),
        amenCount: 0,
        replyCount: 0,
        parentCommentId: parentCommentId
    )
}

private func makeThread(
    contextType: ReplyContextType,
    hasPost: Bool = true,
    visibilityState: ReplyVisibilityState = .visible,
    parentAuthorUsername: String? = nil,
    parentAuthorName: String? = nil,
    parentPreviewText: String? = nil,
    comment: AMENAPP.Comment? = nil
) -> ReplyThread {
    let post: Post? = hasPost ? Post(
        firebaseId: "p1",
        authorId: "u1",
        authorName: "Author",
        authorUsername: "author",
        authorInitials: "A",
        authorProfileImageURL: nil,
        content: "Original post content",
        category: .openTable,
        visibility: .everyone,
        createdAt: Date(),
        amenCount: 0,
        commentCount: 0,
        repostCount: 0,
        mediaItems: []
    ) : nil
    return ReplyThread(
        originalPost: post,
        userReply: comment ?? makeComment(),
        contextType: contextType,
        visibilityState: visibilityState,
        parentCommentId: parentAuthorUsername != nil ? "parent-1" : nil,
        parentAuthorName: parentAuthorName,
        parentAuthorUsername: parentAuthorUsername,
        parentPreviewText: parentPreviewText
    )
}

// MARK: - ReplyFilter Tests

@Suite("ReplyFilter")
struct ReplyFilterTests {

    @Test("All filter matches every context type")
    func allFilterMatchesAll() {
        let contexts: [ReplyContextType] = [.post, .prayer, .verseDiscussion, .churchNote, .berean]
        for ctx in contexts {
            let thread = makeThread(contextType: ctx)
            #expect(ReplyFilter.all.matches(thread),
                    "Expected .all to match contextType .\(ctx)")
        }
    }

    @Test("Verse filter only matches verseDiscussion")
    func verseFilterMatchesOnlyVerse() {
        #expect(ReplyFilter.verse.matches(makeThread(contextType: .verseDiscussion)))
        #expect(!ReplyFilter.verse.matches(makeThread(contextType: .post)))
        #expect(!ReplyFilter.verse.matches(makeThread(contextType: .prayer)))
        #expect(!ReplyFilter.verse.matches(makeThread(contextType: .churchNote)))
        #expect(!ReplyFilter.verse.matches(makeThread(contextType: .berean)))
    }

    @Test("Prayer filter only matches prayer")
    func prayerFilterMatchesOnlyPrayer() {
        #expect(ReplyFilter.prayer.matches(makeThread(contextType: .prayer)))
        #expect(!ReplyFilter.prayer.matches(makeThread(contextType: .post)))
        #expect(!ReplyFilter.prayer.matches(makeThread(contextType: .verseDiscussion)))
        #expect(!ReplyFilter.prayer.matches(makeThread(contextType: .churchNote)))
        #expect(!ReplyFilter.prayer.matches(makeThread(contextType: .berean)))
    }

    @Test("Notes filter only matches churchNote")
    func notesFilterMatchesOnlyChurchNote() {
        #expect(ReplyFilter.notes.matches(makeThread(contextType: .churchNote)))
        #expect(!ReplyFilter.notes.matches(makeThread(contextType: .post)))
        #expect(!ReplyFilter.notes.matches(makeThread(contextType: .prayer)))
        #expect(!ReplyFilter.notes.matches(makeThread(contextType: .verseDiscussion)))
        #expect(!ReplyFilter.notes.matches(makeThread(contextType: .berean)))
    }

    @Test("All cases are enumerable and non-empty")
    func allCasesPresent() {
        #expect(ReplyFilter.allCases.count == 4)
        #expect(ReplyFilter.allCases.contains(.all))
        #expect(ReplyFilter.allCases.contains(.verse))
        #expect(ReplyFilter.allCases.contains(.prayer))
        #expect(ReplyFilter.allCases.contains(.notes))
    }
}

// MARK: - ReplyThread.canOpenThread Tests

@Suite("ReplyThread.canOpenThread")
struct ReplyThreadCanOpenTests {

    @Test("Returns true when post is available")
    func canOpenWhenPostPresent() {
        let thread = makeThread(contextType: .post, hasPost: true)
        #expect(thread.canOpenThread)
    }

    @Test("Returns false when post is nil (deleted/unavailable)")
    func cannotOpenWhenPostNil() {
        let thread = makeThread(contextType: .post, hasPost: false)
        #expect(!thread.canOpenThread)
    }

    @Test("canOpenThread is independent of visibilityState")
    func canOpenIgnoresVisibility() {
        // A thread with a post but hidden reply should still allow opening the thread.
        let thread = makeThread(contextType: .post, hasPost: true, visibilityState: .hidden)
        #expect(thread.canOpenThread)
    }
}

// MARK: - ReplyThread.replyTargetDisplay Tests

@Suite("ReplyThread.replyTargetDisplay")
struct ReplyTargetDisplayTests {

    @Test("Prefers parentAuthorUsername when set")
    func usesParentUsername() {
        let thread = makeThread(
            contextType: .post,
            parentAuthorUsername: "maya",
            parentAuthorName: "Maya Johnson"
        )
        #expect(thread.replyTargetDisplay == "@maya")
    }

    @Test("Falls back to parentAuthorName when username is nil")
    func fallsBackToParentName() {
        let thread = makeThread(
            contextType: .post,
            parentAuthorUsername: nil,
            parentAuthorName: "Maya Johnson"
        )
        #expect(thread.replyTargetDisplay == "Maya Johnson")
    }

    @Test("Falls back to post author username when no parent info")
    func fallsBackToPostAuthorUsername() {
        // No parent info — should use the post's authorUsername.
        let thread = makeThread(contextType: .post, hasPost: true)
        // makeThread's post has authorUsername: "author"
        #expect(thread.replyTargetDisplay == "@author")
    }

    @Test("Falls back to 'this conversation' when nothing is available")
    func fallsBackToGeneric() {
        let thread = makeThread(contextType: .post, hasPost: false)
        #expect(thread.replyTargetDisplay == "this conversation")
    }
}

// MARK: - ReplyThread.previewText Tests

@Suite("ReplyThread.previewText")
struct ReplyPreviewTextTests {

    @Test("Prefers parentPreviewText when set")
    func prefersParentPreview() {
        let thread = makeThread(
            contextType: .post,
            parentPreviewText: "Please pray with me about this."
        )
        #expect(thread.previewText == "Please pray with me about this.")
    }

    @Test("Falls back to post content when parentPreviewText is nil")
    func fallsBackToPostContent() {
        let thread = makeThread(contextType: .post, hasPost: true, parentPreviewText: nil)
        #expect(thread.previewText == "Original post content")
    }

    @Test("Returns nil when parentPreviewText and post are both absent")
    func returnsNilWhenNothingAvailable() {
        let thread = makeThread(contextType: .post, hasPost: false, parentPreviewText: nil)
        #expect(thread.previewText == nil)
    }

    @Test("Empty parentPreviewText falls back to post content")
    func emptyParentPreviewFallsBack() {
        let thread = makeThread(contextType: .post, hasPost: true, parentPreviewText: "")
        #expect(thread.previewText == "Original post content")
    }
}

// MARK: - ReplyVisibilityState Tests

@Suite("ReplyVisibilityState")
struct ReplyVisibilityStateTests {

    @Test("Visible state has no banner")
    func visibleHasNoBanner() {
        #expect(ReplyVisibilityState.visible.bannerText == nil)
        #expect(ReplyVisibilityState.visible.bannerIcon == nil)
    }

    @Test("pendingApproval has clock icon")
    func pendingApprovalHasClockIcon() {
        #expect(ReplyVisibilityState.pendingApproval.bannerIcon == "clock")
        #expect(ReplyVisibilityState.pendingApproval.bannerText == "Pending approval")
    }

    @Test("hidden has eye.slash icon")
    func hiddenHasEyeSlashIcon() {
        #expect(ReplyVisibilityState.hidden.bannerIcon == "eye.slash")
        #expect(ReplyVisibilityState.hidden.bannerText == "Hidden reply")
    }

    @Test("parentDeleted has trash icon")
    func parentDeletedHasTrashIcon() {
        #expect(ReplyVisibilityState.parentDeleted.bannerIcon == "trash")
        #expect(ReplyVisibilityState.parentDeleted.bannerText == "Original post was deleted")
    }

    @Test("parentUnavailable has warning icon")
    func parentUnavailableHasWarningIcon() {
        #expect(ReplyVisibilityState.parentUnavailable.bannerIcon == "exclamationmark.triangle")
        #expect(ReplyVisibilityState.parentUnavailable.bannerText == "Original post unavailable")
    }

    @Test("All non-visible states have both bannerText and bannerIcon")
    func allNonVisibleStatesHaveBanner() {
        let nonVisible: [ReplyVisibilityState] = [.pendingApproval, .hidden, .parentDeleted, .parentUnavailable]
        for state in nonVisible {
            #expect(state.bannerText != nil, "Expected bannerText for \(state)")
            #expect(state.bannerIcon != nil, "Expected bannerIcon for \(state)")
        }
    }
}

// MARK: - Pagination Trigger Logic Tests

@Suite("Pagination trigger — isLastFilteredItem guard")
struct PaginationTriggerTests {

    private func makeThreads(count: Int, contextType: ReplyContextType = .post) -> [ReplyThread] {
        (0..<count).map { i in
            makeThread(contextType: contextType, comment: makeComment(id: "c\(i)"))
        }
    }

    @Test("isLastFilteredItem is true for the last thread in a filtered list")
    func lastFilteredItemDetected() {
        let threads = makeThreads(count: 5)
        let filter = ReplyFilter.all
        let filtered = threads.filter { filter.matches($0) }
        let last = filtered.last

        // The fifth thread should be identified as last.
        #expect(last?.id == threads[4].id)
        #expect(threads[4].id == filtered.last?.id)
    }

    @Test("Sparse filter: only matching threads appear in filtered list")
    func sparseFilterCorrectlyReducesList() {
        var threads: [ReplyThread] = makeThreads(count: 4, contextType: .post)
        // Insert one prayer thread in position 2.
        threads.insert(makeThread(contextType: .prayer, comment: makeComment(id: "prayer-1")), at: 2)

        let filtered = threads.filter { ReplyFilter.prayer.matches($0) }
        #expect(filtered.count == 1)
        #expect(filtered.first?.id == "prayer-1")
        // The prayer thread is the last (and only) filtered item.
        #expect(filtered.last?.id == "prayer-1")
    }

    @Test("isNearEndOfSource triggers for last 3 source items")
    func nearEndOfSourceTriggers() {
        let threads = makeThreads(count: 10)
        // Items at index 7, 8, 9 are near the end (>= count - 3).
        let threshold = max(threads.count - 3, 0) // 7
        for (i, thread) in threads.enumerated() {
            let sourceIndex = threads.firstIndex(where: { $0.id == thread.id }) ?? -1
            let isNear = sourceIndex >= threshold
            if i >= 7 {
                #expect(isNear, "Expected isNearEnd=true for index \(i)")
            } else {
                #expect(!isNear, "Expected isNearEnd=false for index \(i)")
            }
        }
    }

    @Test("ReplyThread identifiable id matches comment id")
    func threadIdMatchesCommentId() {
        let comment = makeComment(id: "comment-abc")
        let thread = makeThread(contextType: .post, comment: comment)
        #expect(thread.id == "comment-abc")
    }
}

// MARK: - ReplyContextType Tests

@Suite("ReplyContextType")
struct ReplyContextTypeTests {

    @Test("post context has no label or icon")
    func postHasNoLabel() {
        #expect(ReplyContextType.post.label == nil)
        #expect(ReplyContextType.post.icon == nil)
    }

    @Test("All non-post types have a label and icon")
    func nonPostTypesHaveMetadata() {
        let typed: [ReplyContextType] = [.prayer, .verseDiscussion, .churchNote, .berean]
        for ctx in typed {
            #expect(ctx.label != nil, "Expected label for \(ctx)")
            #expect(ctx.icon != nil, "Expected icon for \(ctx)")
        }
    }

    @Test("prayer context has correct label")
    func prayerLabel() {
        #expect(ReplyContextType.prayer.label == "Prayer")
    }

    @Test("churchNote context has correct label")
    func churchNoteLabel() {
        #expect(ReplyContextType.churchNote.label == "Church Note")
    }
}
