import Testing
import Foundation
@testable import AMENAPP

// MARK: - Equatable conformance (test-only, not visible to production code)

extension ProfileSessionState: Equatable {
    public static func == (lhs: ProfileSessionState, rhs: ProfileSessionState) -> Bool {
        lhs.bereanThreadDrafts == rhs.bereanThreadDrafts &&
        lhs.lastActiveSurface == rhs.lastActiveSurface &&
        lhs.badgeSnapshot == rhs.badgeSnapshot &&
        lhs.updatedAt == rhs.updatedAt &&
        lhs.composerDrafts.keys.sorted() == rhs.composerDrafts.keys.sorted() &&
        lhs.readCursors.keys.sorted() == rhs.readCursors.keys.sorted() &&
        lhs.scrollPositions.keys.sorted() == rhs.scrollPositions.keys.sorted()
    }
}

extension BadgeCounts: Equatable {
    public static func == (lhs: BadgeCounts, rhs: BadgeCounts) -> Bool {
        lhs.dmUnread == rhs.dmUnread &&
        lhs.notificationUnread == rhs.notificationUnread &&
        lhs.prayerUnread == rhs.prayerUnread
    }
}

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

    @Test("Round-trip: snapshot then restore returns identical state")
    func testRoundTrip() async throws {
        let store = ProfileSessionStore()
        let profileId = uniqueID("roundtrip")
        let original = makeState()

        try await store.snapshot(original, for: profileId)
        let restored = try await store.restore(for: profileId)

        // Cleanup before any assertion so a test failure still leaves Keychain tidy.
        try await store.clear(for: profileId)

        #expect(restored == original)
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
        // store must return .empty rather than throw or surface A's data.
        let resultForB = try await store.restore(for: profileB)

        try await store.clear(for: profileA)
        try await store.clear(for: profileB)

        // The contract: profileB gets .empty (its file simply does not exist).
        #expect(resultForB == .empty)
        // Explicit guard: the sensitive badge count from A must not bleed through.
        #expect(resultForB.badgeSnapshot.dmUnread == 0)
    }

    @Test("Empty restore: never-written profile returns .empty")
    func testEmptyRestore() async throws {
        let store = ProfileSessionStore()
        let profileId = uniqueID("empty")

        let result = try await store.restore(for: profileId)

        // No clear needed — nothing was written.
        #expect(result == .empty)
        #expect(result.composerDrafts.isEmpty)
        #expect(result.bereanThreadDrafts.isEmpty)
        #expect(result.badgeSnapshot == .zero)
    }

    @Test("Clear: snapshot then clear then restore returns .empty")
    func testClear() async throws {
        let store = ProfileSessionStore()
        let profileId = uniqueID("clear")
        let state = makeState(surface: "inbox", badge: 5)

        try await store.snapshot(state, for: profileId)
        try await store.clear(for: profileId)
        let afterClear = try await store.restore(for: profileId)

        #expect(afterClear == .empty)
        #expect(afterClear.lastActiveSurface == nil)
        #expect(afterClear.badgeSnapshot.dmUnread == 0)
    }
}
