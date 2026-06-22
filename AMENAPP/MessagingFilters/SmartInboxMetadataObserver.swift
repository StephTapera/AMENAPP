//
//  SmartInboxMetadataObserver.swift
//  AMENAPP
//
//  System 36 — Phase 4 signal source.
//
//  Subscribes to per-user inbox metadata documents written by the backend
//  `onMessageCreatedForSmartInbox` Cloud Function, plus the user's own
//  `blockedUsers` collection. Publishes three sets that the inbox filter
//  capability layer consumes:
//
//      - prayerRequestConversationIds  (server-set on inboxMetadata.hasPrayerRequest)
//      - safetyReviewConversationIds   (server-set on inboxMetadata.needsSafetyReview)
//      - blockedConversationIds        (mapped from blockedUsers ↔ conversation participants)
//
//  Hard rules:
//    - The observer NEVER infers signals locally. If the backend has not yet
//      written a metadata doc, the corresponding set stays empty.
//    - Listeners are only attached when `messagingSmartInboxCountsEnabled`
//      is ON. When OFF, sets are always empty (matches the function gate).
//    - Listeners are torn down on deinit and when the active conversation
//      set shrinks, to avoid unbounded Firestore traffic.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@available(iOS 17.0, *)
@MainActor
public final class SmartInboxMetadataObserver: ObservableObject {

    @Published public private(set) var prayerRequestConversationIds: Set<String> = []
    @Published public private(set) var safetyReviewConversationIds: Set<String> = []
    @Published public private(set) var blockedConversationIds: Set<String> = []

    /// Hard cap on concurrent inboxMetadata listeners. Power-user safeguard:
    /// for inboxes >50 active threads the observer attaches the cap to the
    /// most recent N conversations only. Smart Inbox filters degrade
    /// gracefully (the un-listened conversations report no signals rather
    /// than fake ones).
    public static let maxConcurrentListeners: Int = 50

    private let db = Firestore.firestore()
    private var metadataListeners: [String: ListenerRegistration] = [:]
    private var blockedListener: ListenerRegistration?
    private var blockedUserIds: Set<String> = []
    private var participantIdByConversationId: [String: String] = [:]

    public init() {}

    deinit {
        for (_, reg) in metadataListeners { reg.remove() }
        blockedListener?.remove()
    }

    /// Attach (or re-attach) listeners for the supplied conversation IDs.
    /// Pass the corresponding `otherParticipantId` map so we can resolve
    /// blocked-user → conversation mapping without re-fetching anywhere.
    /// Pass `enabled: false` to clear all signals immediately.
    public func update(
        conversations: [(id: String, otherParticipantId: String?)],
        currentUserId: String?,
        enabled: Bool
    ) {
        guard enabled, let uid = currentUserId, !uid.isEmpty else {
            clearAllListeners()
            prayerRequestConversationIds = []
            safetyReviewConversationIds = []
            blockedConversationIds = []
            return
        }

        attachBlockedListenerIfNeeded(currentUserId: uid)

        var newParticipantMap: [String: String] = [:]
        for c in conversations {
            if let other = c.otherParticipantId, !other.isEmpty {
                newParticipantMap[c.id] = other
            }
        }
        participantIdByConversationId = newParticipantMap
        recomputeBlockedConversationIds()

        // Cap the listener set to the first N conversations (caller passes
        // them in display order — most recent first). This keeps Firestore
        // read costs bounded for power users with hundreds of DMs.
        let capped = conversations.prefix(Self.maxConcurrentListeners).map(\.id)
        let newIds = Set(capped)
        let oldIds = Set(metadataListeners.keys)

        for stale in oldIds.subtracting(newIds) {
            metadataListeners[stale]?.remove()
            metadataListeners.removeValue(forKey: stale)
            prayerRequestConversationIds.remove(stale)
            safetyReviewConversationIds.remove(stale)
        }

        for fresh in newIds.subtracting(oldIds) {
            attachMetadataListener(conversationId: fresh, currentUserId: uid)
        }
    }

    // MARK: - Private

    private func attachMetadataListener(conversationId: String, currentUserId: String) {
        let ref = db
            .collection("conversations").document(conversationId)
            .collection("inboxMetadata").document(currentUserId)

        let reg = ref.addSnapshotListener { [weak self] snap, _ in
            Task { @MainActor in
                guard let self else { return }
                let data = snap?.data() ?? [:]
                let hasPrayer = (data["hasPrayerRequest"] as? Bool) == true
                let needsReview = (data["needsSafetyReview"] as? Bool) == true
                self.applyMetadata(
                    conversationId: conversationId,
                    hasPrayer: hasPrayer,
                    needsReview: needsReview
                )
            }
        }
        metadataListeners[conversationId] = reg
    }

    private func applyMetadata(conversationId: String, hasPrayer: Bool, needsReview: Bool) {
        if hasPrayer { prayerRequestConversationIds.insert(conversationId) }
        else { prayerRequestConversationIds.remove(conversationId) }

        if needsReview { safetyReviewConversationIds.insert(conversationId) }
        else { safetyReviewConversationIds.remove(conversationId) }
    }

    private func attachBlockedListenerIfNeeded(currentUserId: String) {
        guard blockedListener == nil else { return }
        let ref = db.collection("users").document(currentUserId).collection("blockedUsers")
        blockedListener = ref.addSnapshotListener { [weak self] snap, _ in
            Task { @MainActor in
                guard let self else { return }
                let ids = snap?.documents.compactMap { doc -> String? in
                    if let uid = doc.data()["userId"] as? String, !uid.isEmpty { return uid }
                    return doc.documentID.isEmpty ? nil : doc.documentID
                } ?? []
                self.blockedUserIds = Set(ids)
                self.recomputeBlockedConversationIds()
            }
        }
    }

    private func recomputeBlockedConversationIds() {
        var result: Set<String> = []
        for (cid, other) in participantIdByConversationId where blockedUserIds.contains(other) {
            result.insert(cid)
        }
        blockedConversationIds = result
    }

    private func clearAllListeners() {
        for (_, reg) in metadataListeners { reg.remove() }
        metadataListeners.removeAll()
        blockedListener?.remove()
        blockedListener = nil
        blockedUserIds = []
        participantIdByConversationId = [:]
    }
}
