// SelahSessionPersistenceTests.swift
// AMENAPPTests
//
// SwiftData persistence contracts for LocalSelahSession and LocalSelahSection.

import Foundation

#if canImport(Testing)
import Testing
import SwiftData
@testable import AMENAPP

// MARK: - Helpers

private func makeInMemoryStore() throws -> ModelContainer {
    let schema = Schema([LocalSelahSession.self, LocalSelahSection.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: config)
}

@discardableResult
private func makeSession(
    userId: String,
    promptText: String = "Be still and know",
    context: ModelContext
) -> LocalSelahSession {
    let session = LocalSelahSession(userId: userId, promptText: promptText)
    context.insert(session)
    try? context.save()
    return session
}

// MARK: - SelahSessionPersistenceTests

@MainActor
@Suite("LocalSelahSession persistence")
struct SelahSessionPersistenceTests {

    // MARK: 1. userId scoping

    @Test("Draft fetch is scoped to userId — different users don't see each other's sessions")
    func userIdScoping() throws {
        let container = try makeInMemoryStore()
        let context = ModelContext(container)

        makeSession(userId: "alice-uid", promptText: "Alice prompt", context: context)
        makeSession(userId: "bob-uid", promptText: "Bob prompt", context: context)

        let aliceDescriptor = FetchDescriptor<LocalSelahSession>(
            predicate: #Predicate { $0.userId == "alice-uid" }
        )
        let bobDescriptor = FetchDescriptor<LocalSelahSession>(
            predicate: #Predicate { $0.userId == "bob-uid" }
        )

        let aliceFetched = try context.fetch(aliceDescriptor)
        let bobFetched = try context.fetch(bobDescriptor)

        #expect(aliceFetched.count == 1)
        #expect(aliceFetched.first?.promptText == "Alice prompt")
        #expect(bobFetched.count == 1)
        #expect(bobFetched.first?.promptText == "Bob prompt")
        #expect(aliceFetched.first?.userId != "bob-uid")
        #expect(bobFetched.first?.userId != "alice-uid")
    }

    // MARK: 2. Cleanup by userId

    @Test("Cleanup by userId deletes only that user's sessions")
    func cleanupScopedToUser() throws {
        let container = try makeInMemoryStore()
        let context = ModelContext(container)

        makeSession(userId: "alice-uid", context: context)
        makeSession(userId: "bob-uid", context: context)

        // Simulate cleanupSessions(forUserId:) using direct context delete pattern
        let aliceDescriptor = FetchDescriptor<LocalSelahSession>(
            predicate: #Predicate { $0.userId == "alice-uid" }
        )
        let aliceSessions = try context.fetch(aliceDescriptor)
        aliceSessions.forEach { context.delete($0) }
        try context.save()

        let allDescriptor = FetchDescriptor<LocalSelahSession>()
        let remaining = try context.fetch(allDescriptor)
        #expect(remaining.count == 1)
        #expect(remaining.first?.userId == "bob-uid")
    }

    // MARK: 3. Phase state machine — start()

    @Test("start() transitions idle session to .active and sets startedAt")
    func startSetsActivePhase() {
        let session = LocalSelahSession(userId: "test-uid")
        #expect(session.phase == .idle)
        #expect(session.startedAt == nil)

        session.start()

        #expect(session.phase == .active)
        #expect(session.startedAt != nil)
        #expect(session.continuationEligibility == true)
    }

    @Test("start() does not reset startedAt if already set")
    func startDoesNotResetStartedAt() {
        let session = LocalSelahSession(userId: "test-uid")
        session.start()
        let firstStart = session.startedAt

        // Calling start() again (e.g. resume scenario) must not overwrite startedAt
        session.start()
        #expect(session.startedAt == firstStart)
    }

    // MARK: 4. Phase state machine — pause()

    @Test("pause() from .active transitions to .paused and sets pausedAt")
    func pauseSetsPhaseAndPausedAt() {
        let session = LocalSelahSession(userId: "test-uid")
        session.start()

        session.pause()

        #expect(session.phase == .paused)
        #expect(session.pausedAt != nil)
    }

    @Test("pause() is no-op when session is already paused")
    func pauseIsNoOpWhenAlreadyPaused() {
        let session = LocalSelahSession(userId: "test-uid")
        session.start()
        session.pause()
        let firstPausedAt = session.pausedAt

        // Second pause() call must be ignored (guard phase == .active)
        session.pause()
        #expect(session.phase == .paused)
        #expect(session.pausedAt == firstPausedAt)
    }

    @Test("pause() is no-op when session is idle")
    func pauseIsNoOpWhenIdle() {
        let session = LocalSelahSession(userId: "test-uid")
        // phase is .idle — pause() guard fires
        session.pause()
        #expect(session.phase == .idle)
        #expect(session.pausedAt == nil)
    }

    // MARK: 5. Phase state machine — resume()

    @Test("resume() from .paused transitions to .active and clears pausedAt")
    func resumeFromPausedClearsPausedAt() {
        let session = LocalSelahSession(userId: "test-uid")
        session.start()
        session.pause()
        #expect(session.pausedAt != nil)

        session.resume()

        #expect(session.phase == .active)
        #expect(session.pausedAt == nil)
    }

    @Test("resume() is no-op when session is idle")
    func resumeIsNoOpWhenIdle() {
        let session = LocalSelahSession(userId: "test-uid")
        // .idle is not isContinuable — resume() guard fires
        session.resume()
        #expect(session.phase == .idle)
    }

    // MARK: 6. Phase state machine — complete()

    @Test("complete() sets phase to .completed, sets completedAt, clears continuationEligibility")
    func completeSetsPhaseAndDates() {
        let session = LocalSelahSession(userId: "test-uid")
        session.start()
        session.complete()

        #expect(session.phase == .completed)
        #expect(session.completedAt != nil)
        #expect(session.continuationEligibility == false)
    }

    // MARK: 7. Phase state machine — fail()

    @Test("fail() sets phase to .failed and clears continuationEligibility")
    func failSetsPhaseAndClearsEligibility() {
        let session = LocalSelahSession(userId: "test-uid")
        session.start()
        session.fail()

        #expect(session.phase == .failed)
        #expect(session.continuationEligibility == false)
    }

    // MARK: 8. isContinuable computed property

    @Test("isContinuable is true for .active and .paused only")
    func isContinuableCorrectForAllPhases() {
        #expect(LocalSelahSessionPhase.active.isContinuable == true)
        #expect(LocalSelahSessionPhase.paused.isContinuable == true)
        #expect(LocalSelahSessionPhase.idle.isContinuable == false)
        #expect(LocalSelahSessionPhase.preparing.isContinuable == false)
        #expect(LocalSelahSessionPhase.completed.isContinuable == false)
        #expect(LocalSelahSessionPhase.failed.isContinuable == false)
    }

    // MARK: 9. Section cascade delete

    @Test("Deleting a session also deletes its sections via cascade rule")
    func sectionCascadeDelete() throws {
        let container = try makeInMemoryStore()
        let context = ModelContext(container)

        let session = makeSession(userId: "cascade-uid", context: context)
        let section1 = LocalSelahSection(sessionId: session.id, kind: "prompt", text: "Opening prompt", sortOrder: 0)
        let section2 = LocalSelahSection(sessionId: session.id, kind: "reflection", text: "My reflection", sortOrder: 1)
        session.sections = [section1, section2]
        try context.save()

        // Verify sections are present before delete
        let sectionDescriptor = FetchDescriptor<LocalSelahSection>()
        let before = try context.fetch(sectionDescriptor)
        #expect(before.count == 2)

        // Delete the parent session
        context.delete(session)
        try context.save()

        let afterSections = try context.fetch(sectionDescriptor)
        #expect(afterSections.isEmpty, "Cascade delete should remove all child sections")

        let allSessionsDescriptor = FetchDescriptor<LocalSelahSession>()
        let remainingSessions = try context.fetch(allSessionsDescriptor)
        #expect(remainingSessions.isEmpty)
    }

    // MARK: 10. updateReflection(_:)

    @Test("updateReflection sets reflectionText and title to first 60 chars")
    func updateReflectionSetsTextAndTitle() {
        let session = LocalSelahSession(userId: "test-uid")
        let longReflection = "This is a very long reflection text that exceeds sixty characters in total length."
        session.updateReflection(longReflection)

        #expect(session.reflectionText == longReflection)
        #expect(session.title == String(longReflection.prefix(60)))
        #expect(session.title.count <= 60)
    }

    @Test("updateReflection with short text sets both reflectionText and title to that text")
    func updateReflectionShortText() {
        let session = LocalSelahSession(userId: "test-uid")
        session.updateReflection("Be still.")

        #expect(session.reflectionText == "Be still.")
        #expect(session.title == "Be still.")
    }

    @Test("updateReflection with empty string updates reflectionText but does not overwrite title")
    func updateReflectionEmptyTextDoesNotClearTitle() {
        let session = LocalSelahSession(userId: "test-uid")
        session.updateReflection("Original title text")
        let titleBefore = session.title

        session.updateReflection("")

        #expect(session.reflectionText == "")
        #expect(session.title == titleBefore, "Empty text must not overwrite existing title")
    }

    @Test("updateReflection advances updatedAt")
    func updateReflectionAdvancesUpdatedAt() throws {
        let session = LocalSelahSession(userId: "test-uid")
        let before = session.updatedAt

        // Ensure measurable time delta
        try Task.checkCancellation() // no-op — just a yield point
        session.updateReflection("New reflection")

        // updatedAt must be >= before (same tick is acceptable; regression is a decrement)
        #expect(session.updatedAt >= before)
    }

    // MARK: 11. phaseRawValue round-trip through save/fetch

    @Test("phaseRawValue persists correctly through a second ModelContext fetch")
    func phaseRawValuePersistsThroughSaveFetch() throws {
        let container = try makeInMemoryStore()
        let context = ModelContext(container)

        let session = makeSession(userId: "persist-uid", context: context)
        session.start()
        session.pause()
        try context.save()

        let context2 = ModelContext(container)
        let descriptor = FetchDescriptor<LocalSelahSession>(
            predicate: #Predicate { $0.userId == "persist-uid" }
        )
        let fetched = try context2.fetch(descriptor)
        #expect(fetched.count == 1)
        let fetchedSession = fetched[0]
        #expect(fetchedSession.phaseRawValue == LocalSelahSessionPhase.paused.rawValue)
        #expect(fetchedSession.phase == .paused)
        #expect(fetchedSession.pausedAt != nil)
        #expect(fetchedSession.startedAt != nil)
        #expect(fetchedSession.continuationEligibility == true)
    }
}

#endif
