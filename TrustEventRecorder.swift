//
//  TrustEventRecorder.swift
//  AMENAPP
//
//  Append-only event recorder for trust-relevant events. Events feed into
//  the TrustScoringEngine for ProofOfHuman and ProofOfCare computation.
//  Every trust-relevant action in the app should be recorded through this service.
//
//  Safety: Events are append-only. No event can be deleted from the client.
//  Audit: Every event has a source field for traceability.
//  Privacy: Events contain metadata summaries, never raw content.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

actor TrustEventRecorder {
    
    static let shared = TrustEventRecorder()
    
    private let db = Firestore.firestore()
    
    // Write buffer to batch events and reduce Firestore writes
    private var eventBuffer: [TrustEvent] = []
    private let maxBufferSize = 10
    private var flushTask: Task<Void, Never>?
    private let flushInterval: TimeInterval = 30  // Flush every 30 seconds
    
    // Deduplication: idempotency keys seen in current session
    private var recentEventKeys: Set<String> = []
    private let maxRecentKeys = 200
    
    private init() {
        schedulePeriodicFlush()
    }

    deinit {
        flushTask?.cancel()
    }
    
    // MARK: - Feature Guard
    
    private var isEnabled: Bool {
        // Access feature flags from nonisolated context
        true  // Actual check happens at call site
    }
    
    // MARK: - Record Event
    
    /// Record a trust-relevant event. Events are buffered and flushed periodically.
    func record(_ event: TrustEvent) async {
        // Dedup check
        let idempotencyKey = "\(event.userId)_\(event.eventType.rawValue)_\(event.relatedEntityId ?? "")_\(Int(event.timestamp.timeIntervalSince1970 / 60))"
        guard !recentEventKeys.contains(idempotencyKey) else { return }
        
        recentEventKeys.insert(idempotencyKey)
        if recentEventKeys.count > maxRecentKeys {
            recentEventKeys.removeFirst()
        }
        
        eventBuffer.append(event)
        
        if eventBuffer.count >= maxBufferSize {
            await flush()
        }
    }
    
    // MARK: - Convenience Recorders
    
    /// Record a post creation event.
    func recordPostCreated(userId: String, postId: String, category: String) async {
        await record(TrustEvent(
            id: UUID().uuidString,
            userId: userId,
            eventType: .postCreated,
            category: .both,
            value: 0.3,
            source: "PostsManager",
            relatedEntityId: postId,
            timestamp: Date(),
            metadata: ["category": category]
        ))
    }
    
    /// Record a comment creation event.
    func recordCommentCreated(userId: String, postId: String, commentLength: Int) async {
        let isMeaningful = commentLength >= 30  // 30+ chars = meaningful reply
        await record(TrustEvent(
            id: UUID().uuidString,
            userId: userId,
            eventType: isMeaningful ? .meaningfulReply : .commentCreated,
            category: .care,
            value: isMeaningful ? 0.5 : 0.1,
            source: "CommentService",
            relatedEntityId: postId,
            timestamp: Date(),
            metadata: ["length": String(commentLength)]
        ))
    }
    
    /// Record composer integrity signals (typed vs pasted ratio).
    func recordComposerIntegrity(userId: String, typedRatio: Double) async {
        await record(TrustEvent(
            id: UUID().uuidString,
            userId: userId,
            eventType: .composerIntegrity,
            category: .human,
            value: typedRatio,
            source: "ComposerIntegrityTracker",
            relatedEntityId: nil,
            timestamp: Date(),
            metadata: nil
        ))
    }
    
    /// Record content flagged by moderation.
    func recordContentFlagged(userId: String, contentId: String, reason: String) async {
        await record(TrustEvent(
            id: UUID().uuidString,
            userId: userId,
            eventType: .contentFlagged,
            category: .both,
            value: -0.5,
            source: "ModerationService",
            relatedEntityId: contentId,
            timestamp: Date(),
            metadata: ["reason": reason]
        ))
    }
    
    /// Record a prayer commitment.
    func recordPrayerCommitment(userId: String, prayerRequestId: String) async {
        await record(TrustEvent(
            id: UUID().uuidString,
            userId: userId,
            eventType: .prayerCommitment,
            category: .care,
            value: 0.3,
            source: "PrayerFollowThroughService",
            relatedEntityId: prayerRequestId,
            timestamp: Date(),
            metadata: nil
        ))
    }
    
    /// Record a prayer follow-up (user came back to check).
    func recordPrayerFollowUp(userId: String, prayerRequestId: String) async {
        await record(TrustEvent(
            id: UUID().uuidString,
            userId: userId,
            eventType: .prayerFollowUp,
            category: .care,
            value: 0.6,
            source: "PrayerFollowThroughService",
            relatedEntityId: prayerRequestId,
            timestamp: Date(),
            metadata: nil
        ))
    }
    
    /// Record that a user was blocked by another user.
    func recordBlockReceived(userId: String, blockerId: String) async {
        await record(TrustEvent(
            id: UUID().uuidString,
            userId: userId,
            eventType: .blockReceived,
            category: .both,
            value: -0.3,
            source: "ModerationService",
            relatedEntityId: blockerId,
            timestamp: Date(),
            metadata: nil
        ))
    }
    
    /// Record that a user was reported.
    func recordReportReceived(userId: String, reporterId: String, reason: String) async {
        await record(TrustEvent(
            id: UUID().uuidString,
            userId: userId,
            eventType: .reportReceived,
            category: .both,
            value: -0.4,
            source: "ModerationService",
            relatedEntityId: reporterId,
            timestamp: Date(),
            metadata: ["reason": reason]
        ))
    }
    
    // MARK: - Flush Buffer
    
    /// Flush all buffered events to Firestore.
    func flush() async {
        guard !eventBuffer.isEmpty else { return }
        
        let eventsToWrite = eventBuffer
        eventBuffer.removeAll()
        
        let batch = db.batch()
        
        for event in eventsToWrite {
            let ref = db.collection("users").document(event.userId)
                .collection("trust").document("events")
                .collection("items").document(event.id)
            do {
                try batch.setData(from: event, forDocument: ref)
            } catch {
                dlog("[TrustEventRecorder] Failed to encode event: \(error.localizedDescription)")
            }
        }
        
        do {
            try await batch.commit()
        } catch {
            dlog("[TrustEventRecorder] Failed to flush \(eventsToWrite.count) events: \(error.localizedDescription)")
            // Re-buffer failed events for retry (capped to prevent infinite growth)
            if eventBuffer.count < maxBufferSize * 3 {
                eventBuffer.append(contentsOf: eventsToWrite)
            }
        }
    }
    
    // MARK: - Periodic Flush
    
    private func schedulePeriodicFlush() {
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(30 * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.flush()
            }
        }
    }
}
