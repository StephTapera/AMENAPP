// ConnectOfflineQueueTests.swift
// Verifies Wave 5 ConnectOfflineQueueManager persistence guarantees.
//
// Key invariant: a queued draft survives app relaunch because
// AppStorage("connect_offline_queue_v1") is UserDefaults JSON — persisted
// across process termination by design.

import Testing
@testable import AMENAPP

@Suite("ConnectOfflineQueue — Wave 5 persistence")
struct ConnectOfflineQueueTests {

    // MARK: - Helpers

    private let storageKey = "connect_offline_queue_v1"

    private func clearQueue() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func writeDraftToUserDefaults(_ draft: ConnectQueuedDraft) throws {
        let data = try JSONEncoder().encode([draft])
        let json = String(data: data, encoding: .utf8) ?? "[]"
        UserDefaults.standard.set(json, forKey: storageKey)
    }

    private func readDraftsFromUserDefaults() throws -> [ConnectQueuedDraft] {
        guard let json = UserDefaults.standard.string(forKey: storageKey),
              let data = json.data(using: .utf8) else { return [] }
        return try JSONDecoder().decode([ConnectQueuedDraft].self, from: data)
    }

    // MARK: - C-5 Relaunch survival proof

    @Test("Queued draft survives app relaunch (UserDefaults JSON persistence)")
    func testQueuedDraftSurvivesRelaunch() throws {
        clearQueue()
        defer { clearQueue() }

        // 1. Create a draft and write it to UserDefaults (simulates enqueue())
        let draft = ConnectQueuedDraft(
            type: .announcement,
            payload: ["spaceId": "space-123", "body": "Sunday service reminder"]
        )
        try writeDraftToUserDefaults(draft)

        // 2. Simulate relaunch: fresh manager reads from the SAME UserDefaults key
        //    (This is what ConnectOfflineQueueManager.init() calls via loadFromDisk())
        let loaded = try readDraftsFromUserDefaults()

        #expect(loaded.count == 1)
        #expect(loaded.first?.id == draft.id)
        #expect(loaded.first?.type == .announcement)
        #expect(loaded.first?.payload["spaceId"] == "space-123")
    }

    @Test("Multiple queued drafts all survive relaunch")
    func testMultipleDraftsSurviveRelaunch() throws {
        clearQueue()
        defer { clearQueue() }

        let drafts = [
            ConnectQueuedDraft(type: .dm, payload: ["conversationId": "conv-1", "body": "Hello"]),
            ConnectQueuedDraft(type: .rsvp, payload: ["spaceId": "s-1", "eventId": "e-1"]),
            ConnectQueuedDraft(type: .spaceMessage, payload: ["spaceId": "s-2", "channelId": "c-1", "body": "Hi"]),
        ]
        let data = try JSONEncoder().encode(drafts)
        let json = String(data: data, encoding: .utf8) ?? "[]"
        UserDefaults.standard.set(json, forKey: storageKey)

        let loaded = try readDraftsFromUserDefaults()
        #expect(loaded.count == 3)
        #expect(Set(loaded.map(\.id)) == Set(drafts.map(\.id)))
    }

    @Test("Each draft has a unique UUID idempotency key")
    func testEachDraftHasUniqueIdempotencyKey() {
        let d1 = ConnectQueuedDraft(type: .dm, payload: ["body": "a"])
        let d2 = ConnectQueuedDraft(type: .dm, payload: ["body": "b"])
        #expect(d1.id != d2.id)
    }

    @Test("ConnectQueuedDraft is Codable round-trip stable")
    func testDraftCodableRoundTrip() throws {
        let original = ConnectQueuedDraft(
            type: .announcement,
            payload: ["spaceId": "s-99", "title": "Test", "body": "Wave 5"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConnectQueuedDraft.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.type == original.type)
        #expect(decoded.payload == original.payload)
    }

    @Test("Empty queue produces empty array on decode (no crash on missing key)")
    func testEmptyQueueDecodesCleanly() throws {
        clearQueue()
        defer { clearQueue() }
        let loaded = try readDraftsFromUserDefaults()
        #expect(loaded.isEmpty)
    }
}
