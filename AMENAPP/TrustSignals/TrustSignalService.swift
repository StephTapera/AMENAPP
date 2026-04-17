// TrustSignalService.swift
// AMENAPP — Proof of Human + Proof of Care
//
// Records trust events from anywhere in the app. Events are the raw, append-only
// data that feeds into TrustScoringEngine.computeScores().
//
// Design principles:
//   - Fire-and-forget: callers don't await, recording is non-blocking
//   - Batched: events are queued in memory and flushed on a debounced timer,
//     avoiding a Firestore write on every single interaction
//   - Server-authoritative path: sensitive events (moderation hits, reports)
//     are written via the writeTrustEvent Cloud Function, not directly
//   - Deduped: same event type + entity within a 5-minute window is collapsed
//   - Configurable: respects trustSignalsEnabled flag
//   - No silent mutations: every flush is logged

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class TrustSignalService {

    static let shared = TrustSignalService()

    // MARK: - State

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    /// In-memory queue. Events are flushed in batches of up to 20.
    private var queue: [TrustEvent] = []

    /// Dedup window: same (userId, eventType, entityId) within this interval is collapsed.
    private let dedupWindow: TimeInterval = 300   // 5 minutes

    /// (userId + eventType + entityId) → last recorded timestamp
    private var recentEvents: [String: Date] = [:]

    /// Debounce timer for flushing
    private var flushWorkItem: DispatchWorkItem?
    private let flushDelay: TimeInterval = 10  // Flush after 10 seconds of inactivity
    private let maxQueueSize = 20              // Immediate flush at this size

    private init() {}

    // MARK: - Public API

    /// Records a trust event. Non-blocking. Deduped. Batched.
    func recordEvent(_ event: TrustEvent) {
        guard AMENFeatureFlags.shared.trustSignalsEnabled else { return }
        guard event.userId == Auth.auth().currentUser?.uid else { return }  // Only own events

        let dedupKey = "\(event.userId)_\(event.eventType.rawValue)_\(event.relatedEntityId ?? "")"
        if let lastTime = recentEvents[dedupKey],
           Date().timeIntervalSince(lastTime) < dedupWindow {
            return  // Deduped
        }
        recentEvents[dedupKey] = event.timestamp

        queue.append(event)

        if queue.count >= maxQueueSize {
            flushWorkItem?.cancel()
            flushNow()
        } else {
            scheduleFlush()
        }
    }

    /// Convenience: records a care event (prayer commitment, step completion, etc.)
    func recordCareEvent(
        type: TrustEvent.TrustEventType,
        value: Double = 0.3,
        relatedEntityId: String? = nil,
        metadata: [String: String]? = nil
    ) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        recordEvent(.init(
            id: UUID().uuidString,
            userId: userId,
            eventType: type,
            category: .care,
            value: value,
            source: "TrustSignalService",
            relatedEntityId: relatedEntityId,
            timestamp: Date(),
            metadata: metadata
        ))
    }

    /// Convenience: records a human signal event (post created, composer integrity, etc.)
    func recordHumanEvent(
        type: TrustEvent.TrustEventType,
        value: Double = 0.2,
        relatedEntityId: String? = nil,
        metadata: [String: String]? = nil
    ) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        recordEvent(.init(
            id: UUID().uuidString,
            userId: userId,
            eventType: type,
            category: .human,
            value: value,
            source: "TrustSignalService",
            relatedEntityId: relatedEntityId,
            timestamp: Date(),
            metadata: metadata
        ))
    }

    /// Records a composer integrity signal (typed vs pasted ratio).
    /// Called by the post composer when a post is submitted.
    func recordComposerIntegrity(typedRatio: Double, postId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        recordEvent(.init(
            id: UUID().uuidString,
            userId: userId,
            eventType: .composerIntegrity,
            category: .human,
            value: max(0.0, min(1.0, typedRatio)),
            source: "ComposerIntegrityTracker",
            relatedEntityId: postId,
            timestamp: Date(),
            metadata: ["typedRatio": String(format: "%.2f", typedRatio)]
        ))
    }

    /// Triggers a score recompute for the current user (throttled internally by TrustScoringEngine).
    func triggerScoreRecompute() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        Task {
            _ = await TrustScoringEngine.shared.computeScores(userId: userId)
        }
    }

    // MARK: - Sensitive Events (Server-Authoritative)

    /// Records a moderation hit via Cloud Function (not client-direct Firestore write).
    /// Used when a user's content is flagged by the moderation pipeline.
    func recordModerationHit(userId: String, relatedEntityId: String, severity: String) {
        guard AMENFeatureFlags.shared.trustSignalsEnabled else { return }
        // These go through Cloud Function to prevent client tampering with moderation records
        Task {
            do {
                _ = try await functions.httpsCallable("writeTrustEvent").call([
                    "userId": userId,
                    "type": TrustEvent.TrustEventType.contentFlagged.rawValue,
                    "metadata": ["entityId": relatedEntityId, "severity": severity]
                ])
            } catch {
                dlog("[TrustSignalService] recordModerationHit CF failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Flush

    private func scheduleFlush() {
        flushWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.flushNow()
        }
        flushWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + flushDelay, execute: item)
    }

    private func flushNow() {
        guard !queue.isEmpty else { return }
        let batch = Array(queue.prefix(maxQueueSize))
        queue.removeFirst(min(batch.count, queue.count))

        Task { [weak self] in
            await self?.persistBatch(batch)
        }

        // If more remain, schedule another flush
        if !queue.isEmpty {
            scheduleFlush()
        }
    }

    private func persistBatch(_ events: [TrustEvent]) async {
        guard !events.isEmpty, let userId = events.first?.userId else { return }

        let firestoreBatch = db.batch()
        for event in events {
            let ref = db.collection("users").document(userId)
                .collection("trust").document("events")
                .collection("items").document(event.id)
            if let data = try? Firestore.Encoder().encode(event) {
                firestoreBatch.setData(data, forDocument: ref)
            }
        }

        do {
            try await firestoreBatch.commit()
            dlog("[TrustSignalService] Flushed \(events.count) trust events")

            // Trigger score recompute after a successful batch flush
            _ = await TrustScoringEngine.shared.computeScores(userId: userId)
        } catch {
            dlog("[TrustSignalService] Batch flush failed: \(error.localizedDescription)")
            // Re-queue failed events (up to 3 retries via flag — not implemented here,
            // as events are low-stakes and silently dropping is acceptable)
        }
    }
}

// MARK: - App Hook Extensions
// Convenient call-site entry points used from other services.

extension TrustSignalService {

    /// Called when a post is successfully created.
    func onPostCreated(postId: String, category: String) {
        recordHumanEvent(
            type: .postCreated,
            value: 0.15,
            relatedEntityId: postId,
            metadata: ["category": category]
        )
    }

    /// Called when a meaningful comment is submitted (length > 50 chars, not a reaction word).
    func onMeaningfulReply(commentId: String) {
        recordCareEvent(
            type: .meaningfulReply,
            value: 0.25,
            relatedEntityId: commentId
        )
    }

    /// Called when a user prays for/commits to a prayer request.
    func onPrayerCommitment(prayerId: String) {
        recordCareEvent(
            type: .prayerCommitment,
            value: 0.3,
            relatedEntityId: prayerId
        )
    }

    /// Called when a user follows up on a prayer they committed to.
    func onPrayerFollowUp(prayerId: String) {
        recordCareEvent(
            type: .prayerFollowUp,
            value: 0.4,
            relatedEntityId: prayerId
        )
    }

    /// Called when a check-in step is completed.
    func onCheckInCompleted(threadId: String) {
        recordCareEvent(
            type: .checkInCompleted,
            value: 0.35,
            relatedEntityId: threadId
        )
    }

    /// Called when a user joins a support thread.
    func onSupportThreadJoined(threadId: String) {
        recordCareEvent(
            type: .supportThreadJoined,
            value: 0.2,
            relatedEntityId: threadId
        )
    }

    /// Called when a user abandons a care commitment (check-in expired, reminder ignored).
    func onCommitmentAbandoned(threadId: String) {
        recordCareEvent(
            type: .commitmentAbandoned,
            value: -0.2,
            relatedEntityId: threadId
        )
    }

    /// Called when account phone/email verification completes.
    func onAccountVerified() {
        recordHumanEvent(type: .accountVerified, value: 0.5)
    }
}
