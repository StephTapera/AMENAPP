// BereanVoiceSessionService.swift
// AMENAPP
//
// Berean Live Voice — Firestore session persistence
//
// Handles creation, mutation, and cleanup of BereanVoiceSession documents.
// No existing files are modified.

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - BereanVoiceSessionService

@MainActor
final class BereanVoiceSessionService: ObservableObject {

    // -------------------------------------------------------------------------
    // MARK: Shared Instance
    // -------------------------------------------------------------------------

    static let shared = BereanVoiceSessionService()

    // -------------------------------------------------------------------------
    // MARK: Dependencies
    // -------------------------------------------------------------------------

    private let db = Firestore.firestore()

    // -------------------------------------------------------------------------
    // MARK: Published State
    // -------------------------------------------------------------------------

    @Published private(set) var currentSession: BereanVoiceSession?

    // -------------------------------------------------------------------------
    // MARK: Private State
    // -------------------------------------------------------------------------

    private var sessionListener: ListenerRegistration?

    // Session-start timestamps keyed by sessionId — used to compute avgLatencyMs.
    private var responseStartTimes: [String: Date] = [:]
    private var responseDurations:  [String: [Double]] = [:]

    // -------------------------------------------------------------------------
    // MARK: Init
    // -------------------------------------------------------------------------

    private init() {}

    // -------------------------------------------------------------------------
    // MARK: Session Lifecycle
    // -------------------------------------------------------------------------

    /// Create a new voice session in Firestore and return it.
    func startSession(mode: BereanVoiceMode, userId: String) async -> BereanVoiceSession {
        let session = BereanVoiceSession(userId: userId, mode: mode)
        do {
            try await db
                .collection("berean_voice_sessions")
                .document(session.id)
                .setData(session.toFirestoreData())
            currentSession = session
            dlog("BereanVoiceSessionService: session started \(session.id)")
        } catch {
            dlog("BereanVoiceSessionService: startSession error — \(error)")
        }
        return session
    }

    /// Mark the session complete and persist the endTime + metrics.
    func endSession(_ session: BereanVoiceSession) async {
        let endTime = Date()
        let durations = responseDurations[session.id] ?? []
        let avg = durations.isEmpty
            ? 0.0
            : durations.reduce(0, +) / Double(durations.count)

        do {
            try await db
                .collection("berean_voice_sessions")
                .document(session.id)
                .updateData([
                    "endTime":       endTime,
                    "isActive":      false,
                    "avgLatencyMs":  avg
                ])
            if currentSession?.id == session.id {
                currentSession = nil
            }
            dlog("BereanVoiceSessionService: session ended \(session.id) avgLatency=\(avg)ms")
        } catch {
            dlog("BereanVoiceSessionService: endSession error — \(error)")
        }

        // Clean up in-memory tracking
        responseDurations.removeValue(forKey: session.id)
        responseStartTimes.removeValue(forKey: session.id)
    }

    // -------------------------------------------------------------------------
    // MARK: Event Logging
    // -------------------------------------------------------------------------

    /// Persist a `BereanVoiceEvent` to `berean_voice_events/{eventId}`.
    func logEvent(_ event: BereanVoiceEvent) async {
        do {
            try await db
                .collection("berean_voice_events")
                .document(event.id)
                .setData(event.toFirestoreData())
        } catch {
            dlog("BereanVoiceSessionService: logEvent error — \(error)")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Incremental Updates
    // -------------------------------------------------------------------------

    /// Update the emotional state on the session document.
    func updateEmotionalState(_ state: BereanEmotionalState, sessionId: String) async {
        do {
            try await db
                .collection("berean_voice_sessions")
                .document(sessionId)
                .updateData(["emotionalState": state.rawValue])
        } catch {
            dlog("BereanVoiceSessionService: updateEmotionalState error — \(error)")
        }
    }

    /// Append a transcript chunk to a subcollection — avoids unbounded in-document array.
    /// Each chunk is stored as a separate document in
    /// `berean_voice_sessions/{sessionId}/transcript/{autoId}`.
    func appendTranscript(_ text: String, sessionId: String) async {
        do {
            try await db
                .collection("berean_voice_sessions")
                .document(sessionId)
                .collection("transcript")
                .addDocument(data: [
                    "text": text,
                    "createdAt": FieldValue.serverTimestamp()
                ])
        } catch {
            dlog("BereanVoiceSessionService: appendTranscript error — \(error)")
        }
    }

    /// Increment the interruption counter.
    func recordInterruption(sessionId: String) async {
        do {
            try await db
                .collection("berean_voice_sessions")
                .document(sessionId)
                .updateData([
                    "interruptionCount": FieldValue.increment(Int64(1))
                ])
        } catch {
            dlog("BereanVoiceSessionService: recordInterruption error — \(error)")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Latency Tracking (in-memory)
    // -------------------------------------------------------------------------

    /// Record the start of a response cycle for latency measurement.
    func markResponseStart(sessionId: String) {
        responseStartTimes[sessionId] = Date()
    }

    /// Record the end of a response cycle and accumulate for avgLatencyMs.
    func markResponseEnd(sessionId: String) {
        guard let start = responseStartTimes[sessionId] else { return }
        let ms = Date().timeIntervalSince(start) * 1000
        responseDurations[sessionId, default: []].append(ms)
        responseStartTimes.removeValue(forKey: sessionId)
    }

    // -------------------------------------------------------------------------
    // MARK: Cleanup
    // -------------------------------------------------------------------------

    /// Delete inactive sessions older than 30 days for a given user.
    func cleanupExpiredSessions(userId: String) async {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        do {
            let snapshot = try await db
                .collection("berean_voice_sessions")
                .whereField("userId",   isEqualTo: userId)
                .whereField("isActive", isEqualTo: false)
                .whereField("startTime", isLessThan: cutoff)
                .getDocuments()

            let batch = db.batch()
            for doc in snapshot.documents {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
            dlog("BereanVoiceSessionService: cleaned up \(snapshot.documents.count) expired session(s)")
        } catch {
            dlog("BereanVoiceSessionService: cleanupExpiredSessions error — \(error)")
        }
    }
}
