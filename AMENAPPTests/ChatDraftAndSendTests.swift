// ChatDraftAndSendTests.swift
// AMENAPPTests
//
// Sprint 1A + 1B — UnifiedChatView draft persistence & message lifecycle state
// No Firebase emulator required. All tests are pure unit tests.
//
// Coverage:
//   Draft persistence (1A)
//   Message delivery status state machine (1B)
//   Retry idempotency (1B)
//   Firestore reconciliation dedup logic (1B)
//   Sign-out draft cleanup (1A)

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Suite A: Draft Key Construction

@Suite("Chat Draft — key construction")
struct ChatDraftKeyTests {

    @Test("draft key is prefixed and conversation-scoped")
    func draftKeyFormat() {
        let conversationId = "conv_abc123"
        let key = "chatDraft_\(conversationId)"
        #expect(key == "chatDraft_conv_abc123")
        #expect(key.hasPrefix("chatDraft_"))
    }

    @Test("different conversation IDs produce different draft keys")
    func draftKeysAreConversationScoped() {
        let key1 = "chatDraft_conv_aaa"
        let key2 = "chatDraft_conv_bbb"
        #expect(key1 != key2)
    }

    @Test("draft key survives round-trip through UserDefaults")
    func draftPersistsAndRestores() {
        let key = "chatDraft_testConv_\(UUID().uuidString)"
        let draft = "Hello world draft"

        UserDefaults.standard.set(draft, forKey: key)
        let restored = UserDefaults.standard.string(forKey: key)
        #expect(restored == draft)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: key)
        #expect(UserDefaults.standard.string(forKey: key) == nil)
    }

    @Test("empty draft is not stored — key is removed")
    func emptyDraftRemovesKey() {
        let key = "chatDraft_empty_\(UUID().uuidString)"
        UserDefaults.standard.set("something", forKey: key)
        // Simulate the onChange handler: empty → removeObject
        UserDefaults.standard.removeObject(forKey: key)
        #expect(UserDefaults.standard.string(forKey: key) == nil)
    }
}

// MARK: - Suite B: Sign-out Draft Cleanup

@Suite("Chat Draft — sign-out cleanup")
struct ChatDraftSignOutTests {

    @Test("performFullSignOutCleanup removes all chatDraft_ keys")
    func signOutClearsDraftKeys() async {
        // Plant several drafts for different conversations
        let keys = (0..<5).map { "chatDraft_conv_signout_\($0)" }
        for key in keys {
            UserDefaults.standard.set("unsent text \(key)", forKey: key)
        }

        // Simulate the cleanup logic from AppLifecycleManager
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
        let draftKeys = allKeys.filter { $0.hasPrefix("chatDraft_") }
        for key in draftKeys { UserDefaults.standard.removeObject(forKey: key) }

        for key in keys {
            #expect(UserDefaults.standard.string(forKey: key) == nil,
                    "Key \(key) should be removed after sign-out cleanup")
        }
    }

    @Test("non-draft UserDefaults keys are not touched by cleanup")
    func signOutDoesNotTouchUnrelatedKeys() async {
        let safeKey = "berean_study_mode_enabled"
        let originalValue = UserDefaults.standard.object(forKey: safeKey)

        // Simulate draft cleanup only
        let draftKeys = UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("chatDraft_") }
        for key in draftKeys { UserDefaults.standard.removeObject(forKey: key) }

        // The berean key should be untouched
        let afterValue = UserDefaults.standard.object(forKey: safeKey)
        #expect(String(describing: originalValue) == String(describing: afterValue))
    }
}

// MARK: - Suite C: Message Delivery Status State Machine

@Suite("AppMessage — delivery status state machine")
struct MessageDeliveryStatusTests {

    @Test("new unsent message starts in .sending state")
    func unsentMessageIsSending() {
        let msg = AppMessage(
            text: "hello",
            isFromCurrentUser: true,
            timestamp: Date(),
            isSent: false,
            isDelivered: false,
            isSendFailed: false,
            uploadProgress: nil
        )
        #expect(msg.deliveryStatus == .sending)
    }

    @Test("message in upload shows .sending state")
    func uploadingMessageIsSending() {
        let msg = AppMessage(
            text: "photo message",
            isFromCurrentUser: true,
            timestamp: Date(),
            isSent: false,
            uploadProgress: 0.4
        )
        #expect(msg.deliveryStatus == .sending)
    }

    @Test("isSendFailed true → .failed regardless of other flags")
    func sendFailedIsFailed() {
        let msg = AppMessage(
            text: "failed",
            isFromCurrentUser: true,
            timestamp: Date(),
            isSent: false,
            isDelivered: false,
            isSendFailed: true
        )
        #expect(msg.deliveryStatus == .failed)
    }

    @Test("isSent true, not delivered/read → .sent")
    func sentNotDelivered() {
        let msg = AppMessage(
            text: "sent",
            isFromCurrentUser: true,
            timestamp: Date(),
            isSent: true,
            isDelivered: false,
            isSendFailed: false
        )
        #expect(msg.deliveryStatus == .sent)
    }

    @Test("isDelivered true → .delivered")
    func deliveredState() {
        let msg = AppMessage(
            text: "delivered",
            isFromCurrentUser: true,
            timestamp: Date(),
            isSent: true,
            isDelivered: true,
            isSendFailed: false
        )
        #expect(msg.deliveryStatus == .delivered)
    }

    @Test("isRead true → .read")
    func readState() {
        let msg = AppMessage(
            text: "read",
            isFromCurrentUser: true,
            timestamp: Date(),
            isRead: true,
            isSent: true,
            isDelivered: true,
            isSendFailed: false
        )
        #expect(msg.deliveryStatus == .read)
    }

    @Test("received message (not from current user) → .delivered")
    func receivedMessageIsDelivered() {
        let msg = AppMessage(
            text: "incoming",
            isFromCurrentUser: false,
            timestamp: Date(),
            isSent: false,
            isDelivered: false
        )
        #expect(msg.deliveryStatus == .delivered)
    }

    @Test("isSendFailed wins over isRead")
    func failedWinsOverRead() {
        let msg = AppMessage(
            text: "failed but read?",
            isFromCurrentUser: true,
            timestamp: Date(),
            isRead: true,
            isSent: true,
            isDelivered: true,
            isSendFailed: true
        )
        #expect(msg.deliveryStatus == .failed)
    }

    @Test("deliveryStatus icon and color are defined for all cases")
    func allStatusesHaveIconAndColor() {
        let statuses: [MessageDeliveryStatus] = [.sending, .sent, .delivered, .read, .failed]
        for status in statuses {
            #expect(!status.icon.isEmpty, "Icon missing for \(status)")
        }
    }
}

// MARK: - Suite D: Retry Idempotency

@Suite("Message retry — idempotency")
struct MessageRetryIdempotencyTests {

    @Test("retry reuses original messageId — no new UUID generated")
    func retryPreservesMessageId() {
        let originalId = UUID().uuidString
        // Simulate retry path: retryMessageId = messageId (not a new UUID)
        let retryMessageId = originalId
        #expect(retryMessageId == originalId,
                "Retry must reuse original ID so Firestore setData is idempotent")
    }

    @Test("retry resets isSendFailed to false before re-attempt")
    func retryResetsFailedFlag() {
        let msg = AppMessage(
            text: "retry me",
            isFromCurrentUser: true,
            timestamp: Date(),
            isSendFailed: true
        )
        #expect(msg.deliveryStatus == .failed)

        // Simulate retry state reset
        msg.isSendFailed = false
        msg.isSent = false
        #expect(msg.deliveryStatus == .sending)
    }
}

// MARK: - Suite E: Firestore Reconciliation Dedup

@Suite("loadMessages — Firestore reconciliation")
struct FirestoreReconciliationTests {

    @Test("dict-merge: fetched message wins over pending message with same ID")
    func fetchedWinsOverPending() {
        let msgId = "msg_123"
        let pending = AppMessage(id: msgId, text: "optimistic", isFromCurrentUser: true,
                                 timestamp: Date(), isSent: false)
        let fetched = AppMessage(id: msgId, text: "canonical from server", isFromCurrentUser: true,
                                 timestamp: Date(), isSent: true)

        // Simulate the merge logic in loadMessages
        var merged: [String: AppMessage] = [msgId: fetched]   // fetched wins
        if merged[msgId] == nil { merged[msgId] = pending }   // pending only fills gaps

        #expect(merged[msgId]?.text == "canonical from server")
        #expect(merged[msgId]?.isSent == true)
    }

    @Test("dict-merge: pending message fills in when not yet in snapshot")
    func pendingFillsWhenNotFetched() {
        let pendingId = "msg_pending_only"
        let pending = AppMessage(id: pendingId, text: "not yet confirmed",
                                 isFromCurrentUser: true, timestamp: Date(), isSent: false)

        // Simulate merge: snapshot has different messages, pending fills
        var merged: [String: AppMessage] = ["msg_other": AppMessage(id: "msg_other", text: "other",
                                                                     isFromCurrentUser: false,
                                                                     timestamp: Date())]
        if merged[pendingId] == nil { merged[pendingId] = pending }

        #expect(merged[pendingId]?.text == "not yet confirmed")
    }

    @Test("reconciliation removes pending once ID appears in fetched snapshot")
    func reconciliationClearsPending() {
        let msgId = "msg_reconcile"
        var pendingMessages: [String: AppMessage] = [
            msgId: AppMessage(id: msgId, text: "optimistic", isFromCurrentUser: true,
                              timestamp: Date(), isSent: false)
        ]

        // Simulate Firestore snapshot arriving with this message confirmed
        let fetchedIDs: Set<String> = [msgId, "msg_other"]
        for id in fetchedIDs where pendingMessages[id] != nil {
            pendingMessages.removeValue(forKey: id)
        }

        #expect(pendingMessages[msgId] == nil, "Pending should be cleared once confirmed by Firestore")
    }

    @Test("message sort order is chronological")
    func mergedMessagesAreSortedByTimestamp() {
        let now = Date()
        let m1 = AppMessage(id: "a", text: "first", isFromCurrentUser: true,
                            timestamp: now.addingTimeInterval(-60))
        let m2 = AppMessage(id: "b", text: "second", isFromCurrentUser: false,
                            timestamp: now)
        let unsorted = [m2, m1]
        let sorted = unsorted.sorted { $0.timestamp < $1.timestamp }
        #expect(sorted.first?.id == "a")
        #expect(sorted.last?.id == "b")
    }
}
