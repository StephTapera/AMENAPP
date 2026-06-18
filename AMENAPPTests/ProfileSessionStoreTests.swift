import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

// MARK: - Test Suite

@Suite("ProfileSessionStore")
struct ProfileSessionStoreTests {

    // Each test uses a unique profileId so tests running in the same process
    // do not share Keychain entries or encrypted files with each other.
    private func uniqueID(_ label: String) -> ProfileID {
        "\(label)-\(UUID().uuidString)"
    }

    private func makeState(surface: String = "feed", badge: Int = 3) -> ProfileSessionState {
        ProfileSessionState(
            composerDrafts: [
                surface: DraftSnapshot(
                    surfaceId: surface,
                    textContent: "Draft for \(surface)",
                    attachmentRefs: [],
                    savedAt: Date(timeIntervalSince1970: 1_718_000_000)
                )
            ],
            bereanThreadDrafts: ["thread-1": "Reply draft"],
            readCursors: [
                surface: ReadCursor(
                    surfaceId: surface,
                    lastSeenId: "post-99",
                    seenAt: Date(timeIntervalSince1970: 1_718_000_000)
                )
            ],
            scrollPositions: [
                surface: ScrollAnchor(
                    surfaceId: surface,
                    anchorId: "post-50",
                    offsetPoints: 42.0
                )
            ],
            lastActiveSurface: surface,
            badgeSnapshot: BadgeCounts(dmUnread: badge, notificationUnread: 1, prayerUnread: 0),
            updatedAt: Date(timeIntervalSince1970: 1_718_000_000)
        )
    }

    private func expectState(_ restored: ProfileSessionState, matches original: ProfileSessionState, surface: String) {
        #expect(restored.bereanThreadDrafts == original.bereanThreadDrafts)
        #expect(restored.lastActiveSurface == original.lastActiveSurface)
        #expect(restored.updatedAt == original.updatedAt)
        #expect(restored.composerDrafts.keys.sorted() == original.composerDrafts.keys.sorted())
        #expect(restored.readCursors.keys.sorted() == original.readCursors.keys.sorted())
        #expect(restored.scrollPositions.keys.sorted() == original.scrollPositions.keys.sorted())

        #expect(restored.composerDrafts[surface]?.surfaceId == original.composerDrafts[surface]?.surfaceId)
        #expect(restored.composerDrafts[surface]?.textContent == original.composerDrafts[surface]?.textContent)
        #expect(restored.composerDrafts[surface]?.attachmentRefs == original.composerDrafts[surface]?.attachmentRefs)
        #expect(restored.composerDrafts[surface]?.savedAt == original.composerDrafts[surface]?.savedAt)

        #expect(restored.readCursors[surface]?.surfaceId == original.readCursors[surface]?.surfaceId)
        #expect(restored.readCursors[surface]?.lastSeenId == original.readCursors[surface]?.lastSeenId)
        #expect(restored.readCursors[surface]?.seenAt == original.readCursors[surface]?.seenAt)

        #expect(restored.scrollPositions[surface]?.surfaceId == original.scrollPositions[surface]?.surfaceId)
        #expect(restored.scrollPositions[surface]?.anchorId == original.scrollPositions[surface]?.anchorId)
        #expect(restored.scrollPositions[surface]?.offsetPoints == original.scrollPositions[surface]?.offsetPoints)

        expectBadge(restored.badgeSnapshot, matches: original.badgeSnapshot)
    }

    private func expectEmptyState(_ state: ProfileSessionState) {
        #expect(state.composerDrafts.isEmpty)
        #expect(state.bereanThreadDrafts.isEmpty)
        #expect(state.readCursors.isEmpty)
        #expect(state.scrollPositions.isEmpty)
        #expect(state.lastActiveSurface == nil)
        #expect(state.updatedAt == .distantPast)
        expectBadge(state.badgeSnapshot, matches: .zero)
    }

    private func expectBadge(_ badge: BadgeCounts, matches expected: BadgeCounts) {
        #expect(badge.dmUnread == expected.dmUnread)
        #expect(badge.notificationUnread == expected.notificationUnread)
        #expect(badge.prayerUnread == expected.prayerUnread)
    }

    @Test("Round-trip: snapshot then restore returns identical state")
    func testRoundTrip() async throws {
        let store = ProfileSessionStore()
        let profileId = uniqueID("roundtrip")
        let original = makeState()

        try await store.snapshot(original, for: profileId)
        let restored = try await store.restore(for: profileId)

        // Cleanup before any assertion so a test failure still leaves Keychain tidy.
        try await store.clear(for: profileId)

        expectState(restored, matches: original, surface: "feed")
        #expect(restored.bereanThreadDrafts["thread-1"] == "Reply draft")
        #expect(restored.lastActiveSurface == "feed")
        #expect(restored.badgeSnapshot.dmUnread == 3)
    }

    @Test("Isolation: profileB cannot read profileA's encrypted state")
    func testIsolation() async throws {
        let store = ProfileSessionStore()
        let profileA = uniqueID("iso-A")
        let profileB = uniqueID("iso-B")
        let stateA = makeState(surface: "dm", badge: 7)

        try await store.snapshot(stateA, for: profileA)

        // profileB has never been written to, so its key will be freshly generated.
        // The AES.GCM decryption of A's ciphertext with B's key must fail, and the
        // store must return an empty state rather than throw or surface A's data.
        let resultForB = try await store.restore(for: profileB)

        try await store.clear(for: profileA)
        try await store.clear(for: profileB)

        expectEmptyState(resultForB)
        // Explicit guard: the sensitive badge count from A must not bleed through.
        #expect(resultForB.badgeSnapshot.dmUnread == 0)
    }

    @Test("Empty restore: never-written profile returns .empty")
    func testEmptyRestore() async throws {
        let store = ProfileSessionStore()
        let profileId = uniqueID("empty")

        let result = try await store.restore(for: profileId)

        // No clear needed because nothing was written.
        expectEmptyState(result)
    }

    @Test("Clear: snapshot then clear then restore returns .empty")
    func testClear() async throws {
        let store = ProfileSessionStore()
        let profileId = uniqueID("clear")
        let state = makeState(surface: "inbox", badge: 5)

        try await store.snapshot(state, for: profileId)
        try await store.clear(for: profileId)
        let afterClear = try await store.restore(for: profileId)

        expectEmptyState(afterClear)
        #expect(afterClear.badgeSnapshot.dmUnread == 0)
    }
}

#endif
